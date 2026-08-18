extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_p1.gd
#
# Verrouille le cablage de banc_p1.gd (decider, cible_pour_decision,
# feu_le_plus_proche) : le placide passe par perception -> attaches +
# proximite -> dominance -> agir, sans code specifique a lui. Les couches
# elles-memes ne sont pas testees ici (deja verrouillees par leurs propres
# tests).
#
# Couverture (detail par scenario ci-dessous) :
# - fabriquer_colon/bouger_vers/bouger_selon ont migre vers
#   scripts/banc_commun.gd (chantier "boite a outils", CARTE.md §6) --
#   verrouilles par test_banc_commun.gd, plus testes ici comme fonctions
#   isolees.
# - _colon_reel_resout_brule_par_le_catalogue construit le colon par
#   BancCommun.fabriquer_colon (chemin reel du banc) face a un feu dont
#   "brule" propose plusieurs verbes -- verrouille que poids_verbes, copiee
#   par fabriquer_colon, evite l'alarme structurelle qui bouclait dans
#   _process de la scene reelle (aucun autre scenario ne fait resoudre
#   "brule" par le catalogue).
# - choses_a_fuir/verbe_action ont migre vers scripts/banc_commun.gd
#   (chantier "choses_a_fuir/verbe_action", CARTE.md §6) -- verrouilles
#   par test_banc_commun.gd, plus testes ici comme fonctions isolees.
#   verbe_action resout la portee depuis proprietes.transformation de la
#   chose ciblee, jamais un rayon en dur : "eteint" a portee, "va vers"
#   au-dela. Portee de test choisie deliberement differente de 0.0 et de
#   toute valeur deja utilisee ailleurs (25.0), pour qu'un defaut
#   silencieux se voie s'il reapparait.
# - portee_travail absente de l'entree resolue : retour neutre "va vers",
#   jamais "eteint" par un 0.0 silencieux, meme a distance nulle (le cas
#   ou un defaut 0.0 produirait le pire faux positif).
# - sans feu, le colon ne bouge pas ; un feu produit une decision et le
#   colon s'en rapproche a chaque tick ; entre deux feux, il vise le plus
#   proche.
# - redecision apres extinction : une cendre (proprietes de menace/
#   saillance retirees) ne doit plus jamais etre visee -- le bug qui a
#   tue l'ancien banc.
# - un nouveau feu reveille un colon inactif (rien -> feu ne apres coup).
# - fanatique/batisseur : ciblage par attache (irremplacable/
#   notre_ouvrage) via cible_pour_decision/feu_le_plus_proche -- le
#   fanatique ignore un feu proche pour sa foret menacee au loin et ne
#   la lache jamais pour la ville qui brule ; le batisseur lache sa
#   foret des que sa ville brule.
# - trois colons (placide/fanatique/batisseur) face a un feu neutre
#   convergent tous vers lui, seul candidat.
# - objets_de/resoudre_chantier/agents_rythme/marquer_eteints ont migre
#   vers scripts/banc_commun.gd (chantier "boite a outils", CARTE.md §6,
#   "Dette extinction/cendre") -- verrouilles par test_banc_commun.gd,
#   plus ici : ce fichier ne teste que le cablage PROPRE a banc_p1.gd.
# - chantier "fuite" : BancCommun.choses_a_fuir filtre, parmi ce qui reste
#   visible, les entrees d'origine proximite dont le verbe RESOLU POUR
#   CETTE SEULE ENTREE (Agir.choisir sur une liste a un element) est
#   oriente "fuite" -- ignore les entrees d'origine attache (pas de
#   position a fuir) et celles dont le verbe resolu n'est pas oriente
#   "fuite".
# - chantier "test dynamique" (scripts/boucle.gd) :
#   _inertie_resiste_a_un_feu_plus_proche_par_mouvement_reel fait avancer
#   un colon par decider_et_memoriser + bouger_vers REELS (jamais une
#   saillance posee a la main, contrairement a
#   _inertie_tient_sur_deux_ticks_via_decider_et_memoriser ci-dessous) --
#   un second feu, injecte pile sur sa trajectoire, ne lui vole jamais sa
#   cible grace a gain_inertie.
# - chantier "occupation" (bloc cassable, banc_p1.gd:mettre_a_jour_occupation) :
#   un AGENT (position, comme Extinction.avancer -- jamais action_en_cours,
#   voir plus bas) a portee_travail d'un chantier pose "occupe" ET gele
#   profil_saillance (jamais perdu) -- proximite.gd ignore deja une chose
#   sans profil_saillance, donc plus personne (l'occupant compris) ne la
#   voit comme candidate. Detection par POSITION, pas par action_en_cours :
#   essaye puis corrige (constat empirique, script jetable) -- une chose
#   gelee n'etant plus salante pour l'occupant non plus, son
#   action_en_cours se vide au tick suivant (Agir.etat_courant le reecrit
#   a chaque tick depuis la decision fraiche, jamais une memoire), ce qui
#   liberait la chose, qui redevenait salante, qui la faisait regeler --
#   "occupe" clignotait a chaque tick. La position, elle, ne bouge pas sans
#   decision (agir_et_deplacer ne deplace que sur decision non nulle) :
#   l'occupation se maintient d'elle-meme. Un agent qui s'eloigne restaure
#   profil_saillance a l'identique ; un chantier termine entre-temps
#   (travail_restant absent) ne ressuscite JAMAIS -- reste inerte comme une
#   cendre. Un seul agent a portee suffit, aucun comptage.

const BancP1 = preload("res://scripts/banc_p1.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")
const Boucle = preload("res://scripts/boucle.gd")
const Ciblage = preload("res://scripts/ciblage.gd")
const Depense = preload("res://scripts/depense.gd")
const Extinction = preload("res://scripts/extinction.gd")
const Monde = preload("res://scripts/monde.gd")
const Objet = preload("res://scripts/objet.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

const CATALOGUE_CHOSES := {
	"feu": { "verbes": ["approcher"] },
}

# Catalogue de canaux (equivalent local a data/canaux.json) : tous les
# colons de ce fichier ne portent que "vue" (aucun "angle" -- degenere en
# sphere, comportement IDENTIQUE a l'ancienne portee unique du colon, voir
# scripts/perception.gd).
const CATALOGUE_CANAUX := {
	"vue": { "geometrie": "cone_oriente" },
}

# Catalogue de profils de saillance (equivalent local a
# data/profils_saillance.json) : la chose "feu" (data/types.json) reference
# desormais "profil_saillance": "feu" au lieu de porter saillance_intrinseque/
# portee_saillance en valeur -- voir scripts/proximite.gd. "feu_intense" sert
# uniquement a _inertie_tient_sur_deux_ticks_via_decider_et_memoriser, ou
# feu_b doit devenir plus saillant que feu_a SANS muter le profil partage
# (une reference ne se surcharge pas par instance).
const PROFILS_SAILLANCE := {
	"feu": { "saillance_intrinseque": 3.0, "portee_saillance": 900.0 },
	"feu_intense": { "saillance_intrinseque": 3.5, "portee_saillance": 900.0 },
}

# PHASE 4 piece 3 (chantier "L'entite comme agent complet") : vide partout
# dans ce fichier -- aucun scenario ici ne teste la deformation elle-meme
# (voir test_proximite_deformation.gd, chemin dedie), seulement que le
# cablage propage bien le parametre jusqu'a Proximite.evaluer.
const CATALOGUE_DEFORMATIONS := {}

# Table de menaces par propriete (data/menaces.json) : lue par
# Attaches.evaluer via decider(), et par cible_pour_decision/
# feu_le_plus_proche (meme detection propriete-rencontre-propriete que
# menace_attache, reutilisee pour retrouver une position).
const MENACES := { "inflammable": "brule" }

# Cle par attache.propriete (irremplacable/notre_ouvrage), pas par nom de
# type -- voir attaches.gd et docs/design.md, "Les archetypes n'existent
# pas". Verbe "approcher" ici (pas "defendre", verbe mort retire de
# data/types_attaches.json -- voir CARTE.md §6) : reutilise le seul verbe
# reellement pese par un colon dans ce depot, juste pour prouver que la
# branche ATTACHE resout bien un verbe via poids_verbes -- fixture locale,
# aucun rapport avec l'usage de "approcher" pour "brule" plus bas.
const CATALOGUE_ACTIONS := {
	"irremplacable": { "verbes": ["approcher"] },
	"notre_ouvrage": { "verbes": ["approcher"] },
	"feu": { "verbes": ["approcher"] },
}

func _init() -> void:
	_sans_feu_le_colon_ne_bouge_pas()
	_colon_se_rapproche_du_feu()
	_colon_va_vers_le_plus_proche()
	_le_colon_redecide_apres_extinction()
	_nouveau_feu_reveille_un_colon_inactif()
	_fanatique_ignore_feu_proche_pour_foret_menacee()
	_chose_pour_decision_rend_la_chose_qui_menace_la_foret()
	_batisseur_lache_foret_quand_la_ville_brule()
	_fanatique_ne_lache_pas_sa_foret_pour_la_ville()
	_trois_colons_feu_neutre_vont_au_plus_proche()
	_verbe_action_resout_portee_depuis_la_transformation_de_la_chose()
	_verbe_action_alarme_sur_portee_travail_absente_sans_defaut_silencieux()
	_colon_reel_resout_brule_par_le_catalogue()
	_choses_a_fuir_filtre_par_verbe_resolu_oriente_fuite()
	_inertie_tient_sur_deux_ticks_via_decider_et_memoriser()
	_inertie_resiste_a_un_feu_plus_proche_par_mouvement_reel()
	_occupation_posee_quand_agent_a_portee_travail()
	_occupation_tient_tant_que_l_agent_reste_a_portee()
	_occupation_retiree_et_profil_restaure_quand_l_agent_s_eloigne()
	_occupation_ne_ressuscite_pas_un_chantier_fini()
	_un_seul_agent_a_portee_suffit_aucun_comptage()
	_engagement_ferme_oscillation_sur_bloc_lent()
	_colon_reel_herite_des_reserves_de_dynamique()
	_reserves_du_colon_reel_decroissent_via_depense_avancer()
	_couleur_de_lit_le_type_pose_jamais_le_defaut()
	_couleur_reserve_lit_le_nom_pose_jamais_le_defaut()
	_etiquette_decision_cas()
	_un_feu_existe_distingue_inflammable_de_brule_reellement()
	_faire_agir_colon_sans_feu_rend_rien_et_ne_bouge_pas()
	_faire_agir_colon_avec_feu_deplace_le_colon_et_redessine_le_noeud()
	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: sans feu immobile, se rapproche d'un feu, vise le plus proche, " +
		"redecide apres extinction, repart sur un nouveau feu, " +
		"fanatique/batisseur/placide ciblent juste selon leurs attaches, " +
		"l'inertie resiste a un feu plus proche sur 11 ticks de mouvement reel, " +
		"l'occupation gele/degele profil_saillance sans jamais ressusciter un chantier fini")
	quit(0)

func _ajouter(monde, id: String, type: String, pos: Vector3) -> Dictionary:
	var types = JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json"))
	# materiaux : chantier "densite effective calculee a la fabrication" --
	# arbre porte desormais "composition" (data/types.json), resolue contre
	# data/materiaux.json ; sans ce catalogue, fabriquer() refuserait la
	# fabrication (voir objet.gd, DENSITE EFFECTIVE, echec fort).
	var materiaux = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	var objet = Objet.fabriquer(id, type, pos, types, materiaux)
	monde.ajouter(objet, type, pos)
	return objet

func _colon(pos: Vector3) -> Dictionary:
	return {
		"position": pos,
		"proprietes": {
			"vitesse": 150.0, "canaux": ["vue"], "canaux_config": {"vue": {"portee": 1600.0}},
			"attaches": [], "forme": {}, "poids_verbes": {},
		},
		"action_en_cours": {},
	}

func _fanatique(pos: Vector3) -> Dictionary:
	return {
		"position": pos,
		"proprietes": {
			"vitesse": 150.0, "canaux": ["vue"], "canaux_config": {"vue": {"portee": 1600.0}},
			"attaches": [{"propriete": "irremplacable", "force": 4.0}],
			"forme": {
				"rayon_liaison": 220.0, "gain_haut": 3.0,
				"plafond_haut": 10.0, "gain_inertie": 2.0, "seuil_ecrasement": 2.5,
			},
			"poids_verbes": {"approcher": 1.0},
		},
		"action_en_cours": {},
	}

func _batisseur(pos: Vector3) -> Dictionary:
	return {
		"position": pos,
		"proprietes": {
			"vitesse": 150.0, "canaux": ["vue"], "canaux_config": {"vue": {"portee": 1600.0}},
			"attaches": [{"propriete": "notre_ouvrage", "force": 2.5}],
			"forme": {
				"rayon_liaison": 220.0, "gain_haut": 2.0,
				"plafond_haut": 6.0, "gain_inertie": 0.4, "seuil_ecrasement": 2.0,
			},
			"poids_verbes": {"approcher": 1.0},
		},
		"action_en_cours": {},
	}

func _sans_feu_le_colon_ne_bouge_pas() -> void:
	var monde := Monde.new()
	var colon := _colon(Vector3(0, 0, 0))
	for i in 20:
		var r := BancP1.decider(colon, monde, CATALOGUE_CANAUX, {}, PROFILS_SAILLANCE, CATALOGUE_DEFORMATIONS,CATALOGUE_CHOSES)
		verif.v(r.decision == null, "sans feu, aucune decision ne doit emerger")
	verif.v(colon.position == Vector3(0, 0, 0), "sans feu, le colon ne doit pas bouger")

func _colon_se_rapproche_du_feu() -> void:
	var monde := Monde.new()
	_ajouter(monde, "feu_1", "feu", Vector3(500, 0, 0))
	var colon := _colon(Vector3(0, 0, 0))
	var derniere_distance: float = colon.position.distance_to(Vector3(500, 0, 0))
	for i in 20:
		var r := BancP1.decider(colon, monde, CATALOGUE_CANAUX, {}, PROFILS_SAILLANCE, CATALOGUE_DEFORMATIONS,CATALOGUE_CHOSES)
		verif.v(r.decision != null, "un feu doit produire une decision")
		colon.position = BancCommun.bouger_vers(colon.position, r.decision.position, colon.proprietes.vitesse, 0.1)
		var d: float = colon.position.distance_to(Vector3(500, 0, 0))
		verif.v(d <= derniere_distance, "le colon doit se rapprocher du feu a chaque tick")
		derniere_distance = d

func _colon_va_vers_le_plus_proche() -> void:
	var monde := Monde.new()
	_ajouter(monde, "feu_lointain", "feu", Vector3(500, 500, 0))
	_ajouter(monde, "feu_proche", "feu", Vector3(120, 120, 0))
	var colon := _colon(Vector3(100, 100, 0))
	var r := BancP1.decider(colon, monde, CATALOGUE_CANAUX, {}, PROFILS_SAILLANCE, CATALOGUE_DEFORMATIONS,CATALOGUE_CHOSES)
	verif.v(r.decision != null, "un feu doit etre vise")
	verif.v(r.decision.chose.id == "feu_proche", "le colon doit viser le feu le plus proche")

# Le bug qui a tue l'ancien banc : un colon reste accroche a un feu qui a
# disparu. decider() ne doit rien se rappeler : une fois le feu devenu
# cendre dans le monde percu, il doit disparaitre des saillances tout seul.
func _le_colon_redecide_apres_extinction() -> void:
	var monde := Monde.new()
	var feu := _ajouter(monde, "feu_1", "feu", Vector3(50, 0, 0))
	var colon := _colon(Vector3(50, 0, 0))

	var avant := BancP1.decider(colon, monde, CATALOGUE_CANAUX, {}, PROFILS_SAILLANCE, CATALOGUE_DEFORMATIONS,CATALOGUE_CHOSES)
	verif.v(avant.decision != null and avant.decision.chose.id == "feu_1",
		"le colon doit d'abord viser le feu")

	# Ce que fait extinction.gd en vrai une fois le feu eteint (_eteindre) :
	# retire la propriete-menace (generique, via MENACES) et la reference
	# "profil_saillance" -- ne mute plus jamais "type". Passe par la
	# reference rendue par _ajouter (jamais monde.choses[0] : un champ
	# interne de Monde, positionnel -- fragile si l'ordre ou la forme
	# de stockage change un jour).
	for vuln in MENACES:
		feu.proprietes.erase(MENACES[vuln])
	feu.proprietes.erase("profil_saillance")

	var apres := BancP1.decider(colon, monde, CATALOGUE_CANAUX, {}, PROFILS_SAILLANCE, CATALOGUE_DEFORMATIONS,CATALOGUE_CHOSES)
	verif.v(apres.decision == null, "une cendre ne doit plus jamais etre visee")

func _nouveau_feu_reveille_un_colon_inactif() -> void:
	var monde := Monde.new()
	var colon := _colon(Vector3(0, 0, 0))

	var avant := BancP1.decider(colon, monde, CATALOGUE_CANAUX, {}, PROFILS_SAILLANCE, CATALOGUE_DEFORMATIONS,CATALOGUE_CHOSES)
	verif.v(avant.decision == null, "rien au depart : aucun feu")

	_ajouter(monde, "feu_2", "feu", Vector3(30, 0, 0))
	var apres := BancP1.decider(colon, monde, CATALOGUE_CANAUX, {}, PROFILS_SAILLANCE, CATALOGUE_DEFORMATIONS,CATALOGUE_CHOSES)
	verif.v(apres.decision != null and apres.decision.chose.id == "feu_2",
		"un nouveau feu doit reveiller le colon inactif, pas rester ignore")

# P6 : la seule regle qui compte. Le feu menace tout le monde pareil
# (proximite, plancher commun) ; ce qui separe les colons, c'est CE QUI
# BRULE (une attache menacee monte par-dessus le plancher).

func _fanatique_ignore_feu_proche_pour_foret_menacee() -> void:
	var monde := Monde.new()
	_ajouter(monde, "feu_colle", "feu", Vector3(110, 100, 0))
	_ajouter(monde, "arbre_lointain", "arbre", Vector3(900, 100, 0))
	_ajouter(monde, "feu_foret", "feu", Vector3(910, 100, 0))
	var colon := _fanatique(Vector3(100, 100, 0))

	var r := BancP1.decider(colon, monde, CATALOGUE_CANAUX, MENACES, PROFILS_SAILLANCE, CATALOGUE_DEFORMATIONS,CATALOGUE_ACTIONS)
	verif.v(r.decision.type == "irremplacable", "la foret menacee doit ecraser le feu colle au fanatique")

	var cible := BancP1.cible_pour_decision(r.decision, r.perceptions, MENACES, colon.position)
	verif.v(cible.distance_to(Vector3(910, 100, 0)) < 1.0,
		"il vise le feu qui menace sa foret, pas celui a ses pieds")

# Ciblage.viser doit remonter la CHOSE (pas seulement sa position) meme
# dans le chemin attache (attaches.gd:evaluer ne rend ni "chose" ni
# "position") : necessaire pour lire proprietes.transformation de la chose
# visee, que cible_pour_decision/feu_le_plus_proche ne remontent jamais.
# Verbe "approcher" absent de data/orientations.json : vise le
# declencheur-menace par defaut, comme avant le chantier "cible generale".
func _chose_pour_decision_rend_la_chose_qui_menace_la_foret() -> void:
	var monde := Monde.new()
	_ajouter(monde, "feu_colle", "feu", Vector3(110, 100, 0))
	_ajouter(monde, "arbre_lointain", "arbre", Vector3(900, 100, 0))
	_ajouter(monde, "feu_foret", "feu", Vector3(910, 100, 0))
	var colon := _fanatique(Vector3(100, 100, 0))

	var r := BancP1.decider(colon, monde, CATALOGUE_CANAUX, MENACES, PROFILS_SAILLANCE, CATALOGUE_DEFORMATIONS,CATALOGUE_ACTIONS)
	var chose = Ciblage.viser(r.decision, r.perceptions, MENACES, {}, {})
	verif.v(chose != null and chose.id == "feu_foret",
		"Ciblage.viser doit rendre la chose qui menace la foret, pas juste sa position")

func _batisseur_lache_foret_quand_la_ville_brule() -> void:
	var monde := Monde.new()
	_ajouter(monde, "batisse_1", "batisse", Vector3(550, 520, 0))
	_ajouter(monde, "feu_foret", "feu", Vector3(1000, 350, 0))
	_ajouter(monde, "feu_batisse", "feu", Vector3(560, 520, 0))
	var colon := _batisseur(Vector3(150, 350, 0))

	var r := BancP1.decider(colon, monde, CATALOGUE_CANAUX, MENACES, PROFILS_SAILLANCE, CATALOGUE_DEFORMATIONS,CATALOGUE_ACTIONS)
	verif.v(r.decision.type == "notre_ouvrage", "la ville qui brule doit dominer la foret lointaine")
	verif.v(r.decision.action == "approcher", "l'action retenue doit etre approcher")

func _fanatique_ne_lache_pas_sa_foret_pour_la_ville() -> void:
	var monde := Monde.new()
	_ajouter(monde, "arbre_1", "arbre", Vector3(900, 100, 0))
	_ajouter(monde, "feu_foret", "feu", Vector3(910, 100, 0))
	_ajouter(monde, "feu_ville", "feu", Vector3(100, 700, 0))
	var colon := _fanatique(Vector3(100, 100, 0))

	var r := BancP1.decider(colon, monde, CATALOGUE_CANAUX, MENACES, PROFILS_SAILLANCE, CATALOGUE_DEFORMATIONS,CATALOGUE_ACTIONS)
	verif.v(r.decision.type == "irremplacable", "le fanatique ne doit pas lacher sa foret pour la ville")

	var cible := BancP1.cible_pour_decision(r.decision, r.perceptions, MENACES, colon.position)
	verif.v(cible.distance_to(Vector3(910, 100, 0)) < 1.0,
		"il reste sur le feu qui menace sa foret, il perd la ville")

func _trois_colons_feu_neutre_vont_au_plus_proche() -> void:
	var monde := Monde.new()
	_ajouter(monde, "feu_neutre", "feu", Vector3(30, 40, 0))
	var noms := ["placide", "fanatique", "batisseur"]
	var colons := [
		_colon(Vector3(0, 0, 0)),
		_fanatique(Vector3(50, 0, 0)),
		_batisseur(Vector3(100, 0, 0)),
	]
	for i in colons.size():
		var colon: Dictionary = colons[i]
		var r := BancP1.decider(colon, monde, CATALOGUE_CANAUX, MENACES, PROFILS_SAILLANCE, CATALOGUE_DEFORMATIONS,CATALOGUE_ACTIONS)
		verif.v(r.decision != null, "%s doit reagir au feu neutre" % noms[i])
		var cible := BancP1.cible_pour_decision(r.decision, r.perceptions, MENACES, colon.position)
		verif.v(cible.distance_to(Vector3(30, 40, 0)) < 1.0,
			"%s doit viser le feu neutre, seul candidat" % noms[i])

# Verrouille BancCommun.verbe_action (descendue de banc_p1.gd cette
# session, chantier "choses_a_fuir/verbe_action") : la portee vient de
# proprietes.transformation de la CHOSE ciblee, resolue dans le catalogue
# transformations recu en parametre -- jamais d'un catalogue de choses par
# nom. Portee choisie
# (42.0) deliberement differente de 0.0 et de 25.0 (deja utilisee ailleurs
# dans le depot, data/transformations.json) : si un defaut ou une valeur
# recopiee par erreur s'y substituait, ce test le verrait.
func _verbe_action_resout_portee_depuis_la_transformation_de_la_chose() -> void:
	var transformations := {
		"decoration_test": {"portee_travail": 42.0},
	}
	var chose := {
		"id": "chose_test",
		"proprietes": {"travail_restant": 5.0, "transformation": "decoration_test"},
	}
	var colon := {"position": Vector3.ZERO}

	var a_portee := BancCommun.verbe_action(colon, Vector3(40, 0, 0), chose, transformations)
	verif.v(a_portee == "eteint",
		"distance 40 <= portee_travail 42 (resolue depuis la transformation de la chose) : eteint")

	var hors_portee := BancCommun.verbe_action(colon, Vector3(50, 0, 0), chose, transformations)
	verif.v(hors_portee == "va vers",
		"distance 50 > portee_travail 42 : va vers")

# Verrouille le seul des cinq cas vises par cette correction qui touche
# directement le risque de defaut silencieux sur portee_travail (les deux
# autres -- chose nulle, pas de chantier -- sont des retours legitimes
# sans alarme, documentes comme tels dans banc_commun.gd:verbe_action).
# transfo.has("portee_travail") == false declenche push_error et un retour
# neutre "va vers", jamais un calcul avec 0.0. Distance choisie A ZERO
# expres : si un defaut 0.0 silencieux s'appliquait a portee, 0.0 <= 0.0
# serait vrai et rendrait "eteint" -- exactement le faux positif qu'un
# defaut silencieux produirait, meme au pire cas.
func _verbe_action_alarme_sur_portee_travail_absente_sans_defaut_silencieux() -> void:
	var transformations := {
		"sans_portee": {},
	}
	var chose := {
		"id": "chose_sans_portee",
		"proprietes": {"travail_restant": 5.0, "transformation": "sans_portee"},
	}
	var colon := {"position": Vector3.ZERO}

	var resultat := BancCommun.verbe_action(colon, Vector3.ZERO, chose, transformations)
	verif.v(resultat == "va vers",
		"portee_travail absente de l'entree resolue : retour neutre 'va vers', " +
		"jamais 'eteint' par un 0.0 silencieux, meme a distance nulle")

# Verrouille le trou qui rendait le bug de production invisible : aucun
# scenario existant ne fait resoudre "brule" par le catalogue --
# CATALOGUE_CHOSES/CATALOGUE_ACTIONS ne portent pas cette cle ("feu" y
# reste une entree morte, voir CARTE.md §4), donc rien ne passait par
# agir.gd:_verbe_par_poids ici. Construit le colon par fabriquer_colon --
# le CHEMIN REEL du banc, jamais les helpers _colon/_fanatique/_batisseur
# de ce fichier, qui contournent fabriquer_colon -- face a un feu dont la
# propriete "brule" propose deux verbes : si fabriquer_colon ne copiait
# pas poids_verbes depuis decl (bug corrige cette session), agir.gd
# alarme (poids_verbes absente) et rend une action vide au lieu du verbe
# pese -- exactement ce qui bouclait dans _process de la scene reelle.
func _colon_reel_resout_brule_par_le_catalogue() -> void:
	var catalogue_types := {
		"colon": {"vitesse": 150.0, "canaux": ["vue"], "canaux_config": {"vue": {"portee": 1600.0}}, "rythme": 1.0},
	}
	var decl := {
		"position": [0.0, 0.0, 0.0],
		"attaches": [],
		"forme": {},
		"poids_verbes": {"eteindre": 1.0, "attiser": -1.0},
	}
	var colon := BancCommun.fabriquer_colon("colon_reel", "colon", decl, catalogue_types)

	var monde := Monde.new()
	_ajouter(monde, "feu_1", "feu", Vector3(10, 0, 0))

	var catalogue_brule := {"brule": {"verbes": ["eteindre", "attiser"]}}
	var r := BancP1.decider(colon, monde, CATALOGUE_CANAUX, {}, PROFILS_SAILLANCE, CATALOGUE_DEFORMATIONS,catalogue_brule)

	verif.v(r.decision != null, "le colon reel doit percevoir le feu")
	if r.decision != null:
		verif.v(r.decision.action == "eteindre",
			"poids_verbes copie par fabriquer_colon depuis decl : le colon eteint, " +
			"n'attise jamais -- sans la copie, agir.gd alarme et l'action reste vide")

# Verrouille BancCommun.choses_a_fuir (descendue de banc_p1.gd cette
# session, chantier "choses_a_fuir/verbe_action") : parmi ce qui reste
# visible, ne retient que les entrees d'origine PROXIMITE (cle "chose")
# dont le verbe RESOLU POUR CETTE SEULE ENTREE (Agir.choisir sur une liste
# a un element) est oriente "fuite" dans orientations -- feu_fuite (propriete "brule",
# poids_verbes["s_eloigner"] positif) est retenu ; eau_calme (propriete
# "eau", verbe "approcher" jamais pese chez ce colon : action vide, donc
# orientation par defaut "declencheur") est ignore ; une entree d'origine
# ATTACHE (pas de "chose") est ignoree meme si presente, faute de
# position a fuir.
func _choses_a_fuir_filtre_par_verbe_resolu_oriente_fuite() -> void:
	var colon := {"proprietes": {"forme": {}, "poids_verbes": {"s_eloigner": 1.0, "approcher": 1.0}}}
	var catalogue_actions := {
		"brule": {"verbes": ["s_eloigner"]},
		"eau": {"verbes": ["approcher"]},
	}
	var orientations := {"s_eloigner": "fuite"}

	var feu_fuite := {"id": "feu_fuite", "position": Vector3(10, 0, 0), "proprietes": {"brule": true}}
	var eau_calme := {"id": "eau_calme", "position": Vector3(20, 0, 0), "proprietes": {"eau": true}}

	var visibles := [
		{"chose": feu_fuite, "type": "feu", "position": Vector3(10, 0, 0), "saillance": 2.0},
		{"chose": eau_calme, "type": "eau", "position": Vector3(20, 0, 0), "saillance": 1.5},
		{"type": "irremplacable", "attache": {"propriete": "irremplacable", "force": 3.0}, "menace": 0.6, "saillance": 5.0},
	]

	var choses := BancCommun.choses_a_fuir(visibles, colon, catalogue_actions, orientations, Monde.new())
	verif.v(choses.size() == 1, "un seul verbe resolu doit etre oriente fuite ici")
	if choses.size() == 1:
		verif.v(choses[0].position == Vector3(10, 0, 0) and choses[0].saillance == 2.0,
			"la chose retenue doit etre feu_fuite (brule -> s_eloigner), pas eau_calme ni l'attache")

# Verrou du fil decider_et_memoriser LUI-MEME, pas de decider()/etat_courant()
# rejoues a la main depuis le test -- le test appelle la fonction que
# _faire_agir_colon appelle, jamais une reimplementation du geste (sinon rien
# ne prouve que le cablage reel memorise). Colon minimal sans attache
# (comme le placide) : attaches: [] suffit, aucune foret/ville necessaire.
# Deux feux a distance nulle du colon (facteur = 1.0) : egalite stricte au
# tick 1, choisir() retient feu_a (premier element, comparaison stricte
# ">"). Entre les deux ticks, feu_b monte a 3.5 (delta 0.5), sous
# gain_inertie (2.0, valeur reelle du fanatique dans data/banc_p1.json) :
# sans memorisation feu_b l'emporterait au tick 2 (3.5 > 3.0) -- avec,
# feu_a tient (3.0 + 2.0 = 5.0 > 3.5). Retirer la ligne d'ecriture DANS
# decider_et_memoriser fait tomber ce test au rouge.
func _inertie_tient_sur_deux_ticks_via_decider_et_memoriser() -> void:
	var colon := {
		"position": Vector3.ZERO,
		"proprietes": {
			"vitesse": 150.0, "canaux": ["vue"], "canaux_config": {"vue": {"portee": 1600.0}},
			"attaches": [], "forme": {"gain_inertie": 2.0},
			"poids_verbes": {"approcher": 1.0},
		},
		"action_en_cours": {},
	}
	var monde := Monde.new()
	var feu_a := _ajouter(monde, "feu_a", "feu", Vector3.ZERO)
	var feu_b := _ajouter(monde, "feu_b", "feu", Vector3.ZERO)

	var r1 := BancP1.decider_et_memoriser(colon, monde, CATALOGUE_CANAUX, {}, PROFILS_SAILLANCE, CATALOGUE_DEFORMATIONS,CATALOGUE_CHOSES)
	verif.v(r1.decision != null and r1.decision.chose.id == "feu_a",
		"tick 1, egalite stricte (3.0 == 3.0) : le premier feu (feu_a) doit etre retenu")

	# Une reference de catalogue ne se surcharge pas par instance (voir
	# scripts/proximite.gd) : pour faire monter la saillance de feu_b SEUL,
	# on le fait pointer vers un profil distinct ("feu_intense", voir
	# PROFILS_SAILLANCE) plutot que muter saillance_intrinseque sur
	# l'instance, qui n'existe plus.
	feu_b.proprietes.profil_saillance = "feu_intense"

	var r2 := BancP1.decider_et_memoriser(colon, monde, CATALOGUE_CANAUX, {}, PROFILS_SAILLANCE, CATALOGUE_DEFORMATIONS,CATALOGUE_CHOSES)
	verif.v(r2.decision != null and r2.decision.chose.id == "feu_a",
		"tick 2, feu_b monte a 3.5 (delta 0.5 < gain_inertie 2.0) : l'inertie doit garder feu_a")

# gain_inertie=2.0 : valeur reelle du fanatique (data/banc_p1.json). Colon
# simple sans attache (comme le placide), gain pose directement sur sa
# forme pour isoler l'effet de l'inertie seule -- aucune attache, aucun
# catalogue de defense necessaire pour ce scenario (saillance de proximite
# pure). vitesse=150.0 : valeur reelle commune a tout colon (data/types.json).
func _colon_inertie_reelle() -> Dictionary:
	return {
		"position": Vector3.ZERO,
		"proprietes": {
			"vitesse": 150.0, "canaux": ["vue"], "canaux_config": {"vue": {"portee": 1600.0}},
			"attaches": [], "forme": {"gain_inertie": 2.0},
			"poids_verbes": {"approcher": 1.0},
		},
		"action_en_cours": {},
	}

# Verrou du canal REEL de l'inertie (chantier "test dynamique") : un colon
# engage sur feu_a (300,0,0) depuis (0,0,0) traverse, EN CHEMIN, la position
# exacte ou un second feu vient d'etre allume -- feu_c est injecte a +60 de
# la position du colon au moment de l'injection (tick 3), pile SUR sa
# trajectoire, entre le colon et feu_a. Sans inertie, feu_c (de plus en
# plus proche a chaque tick, jusqu'a saillance MAXIMALE quand le colon
# marche dessus) volerait la cible des l'injection ; avec gain_inertie=2.0
# (valeur reelle du fanatique), feu_a reste engage du debut a la fin,
# meme au tick ou le colon est exactement sur feu_c (distance 0, saillance
# 3.0 -- le pire cas pour l'inertie) -- calibre empiriquement (harnais
# jetable, non conserve).
func _inertie_resiste_a_un_feu_plus_proche_par_mouvement_reel() -> void:
	var monde := Monde.new()
	var feu_a := _ajouter(monde, "feu_a", "feu", Vector3(300.0, 0.0, 0.0))
	var colon := _colon_inertie_reelle()
	var geste := Callable(BancP1, "agir_et_deplacer").bind(monde, CATALOGUE_CANAUX, {}, PROFILS_SAILLANCE, CATALOGUE_DEFORMATIONS,CATALOGUE_CHOSES, {}, {}, {}, {}, 0.3)

	var avant := Boucle.tracer(colon, 3, geste)
	for d in avant:
		verif.v(d != null and d.chose.id == "feu_a", "avant injection, seul feu_a existe : la cible doit etre feu_a")

	_ajouter(monde, "feu_c", "feu", colon.position + Vector3(60.0, 0.0, 0.0))

	var apres := Boucle.tracer(colon, 8, geste)
	for d in apres:
		verif.v(d != null and d.chose.id == "feu_a",
			"gain_inertie=2.0 (valeur reelle) doit garder feu_a engage, meme quand le colon marche exactement sur feu_c")
	verif.v(colon.position.distance_to(feu_a.position) < 1.0,
		"le colon doit finir par atteindre feu_a, jamais devie vers feu_c")

# Chantier "occupation" (mettre_a_jour_occupation) : portee_travail reelle
# (25.0, data/transformations.json) portee ici en local, meme convention
# que PROFILS_SAILLANCE/CATALOGUE_CHOSES plus haut -- pas de dependance au
# disque dans ce fichier.
const TRANSFORMATIONS_OCCUPATION := {
	"defaut": {"portee_travail": 25.0},
}

func _chose_chantier(id: String, pos: Vector3) -> Dictionary:
	return {
		"id": id, "position": pos,
		"proprietes": {"profil_saillance": "bloc", "travail_restant": 3.0, "transformation": "defaut"},
	}

# agent : MEME forme que BancCommun.agents_rythme rend deja a Extinction.avancer
# ({ position, rythme facultatif }) -- mettre_a_jour_occupation detecte par
# POSITION, jamais par action_en_cours (voir banc_p1.gd, constat empirique :
# detecter par action_en_cours faisait clignoter "occupe" a chaque tick, la
# chose gelee n'etant plus salante pour l'occupant non plus, qui vidait donc
# sa propre action_en_cours au tick suivant).
func _agent(pos: Vector3) -> Dictionary:
	return {"position": pos}

# Distance 10 <= portee_travail 25 : l'agent est a portee -- "occupe" pose,
# profil_saillance GELE (pas perdu, voir banc_p1.gd:mettre_a_jour_occupation)
# sous "profil_saillance_gele".
func _occupation_posee_quand_agent_a_portee_travail() -> void:
	var monde := Monde.new()
	var chose := _chose_chantier("bloc_1", Vector3(10, 0, 0))
	monde.ajouter(chose, "bloc", chose.position)

	BancP1.mettre_a_jour_occupation(monde, [_agent(Vector3(0, 0, 0))], TRANSFORMATIONS_OCCUPATION)

	verif.v(chose.proprietes.get("occupe", false), "un agent a portee_travail doit poser 'occupe'")
	verif.v(not chose.proprietes.has("profil_saillance"), "la chose occupee ne doit plus etre saillante pour personne")
	verif.v(chose.proprietes.get("profil_saillance_gele", "") == "bloc",
		"le profil_saillance d'origine doit etre gele intact, jamais perdu")

# L'occupation TIENT sur plusieurs appels tant que l'agent reste a portee --
# la chose reste NON saillante meme pour lui-meme, sans jamais se degeler
# toute seule (le bug de clignotement que la detection par action_en_cours
# produisait, verifie empiriquement puis corrige).
func _occupation_tient_tant_que_l_agent_reste_a_portee() -> void:
	var monde := Monde.new()
	var chose := _chose_chantier("bloc_1", Vector3(10, 0, 0))
	monde.ajouter(chose, "bloc", chose.position)
	var agents := [_agent(Vector3(0, 0, 0))]

	for i in 5:
		BancP1.mettre_a_jour_occupation(monde, agents, TRANSFORMATIONS_OCCUPATION)
		verif.v(chose.proprietes.get("occupe", false), "l'occupation doit tenir a chaque appel (tick %d), jamais clignoter" % i)
		verif.v(not chose.proprietes.has("profil_saillance"), "reste non saillante tant que l'agent est a portee (tick %d)" % i)

# L'agent s'eloigne (hors portee_travail) : "occupe" doit se retirer et
# profil_saillance revenir EXACTEMENT a sa valeur d'avant le gel -- la
# chose redevient attractive pour tous.
func _occupation_retiree_et_profil_restaure_quand_l_agent_s_eloigne() -> void:
	var monde := Monde.new()
	var chose := _chose_chantier("bloc_1", Vector3(10, 0, 0))
	monde.ajouter(chose, "bloc", chose.position)

	BancP1.mettre_a_jour_occupation(monde, [_agent(Vector3(0, 0, 0))], TRANSFORMATIONS_OCCUPATION)
	verif.v(chose.proprietes.get("occupe", false), "verrou intermediaire : doit etre occupee avant que l'agent s'eloigne")

	BancP1.mettre_a_jour_occupation(monde, [_agent(Vector3(9999, 0, 0))], TRANSFORMATIONS_OCCUPATION)

	verif.v(not chose.proprietes.has("occupe"), "plus aucun agent a portee : 'occupe' doit se retirer")
	verif.v(chose.proprietes.get("profil_saillance", "") == "bloc",
		"le profil_saillance doit etre restaure a l'identique, la chose redevient attractive")
	verif.v(not chose.proprietes.has("profil_saillance_gele"), "le gel ne doit laisser aucune trace une fois restaure")

# Si le chantier s'est termine PENDANT l'occupation (travail_restant/
# transformation retires par extinction.gd:_appliquer_a_zero), la chose ne
# doit JAMAIS retrouver sa saillance : une transformation qui l'a
# intentionnellement effacee ne se laisse pas ressusciter par ce cablage.
func _occupation_ne_ressuscite_pas_un_chantier_fini() -> void:
	var monde := Monde.new()
	var chose := _chose_chantier("bloc_1", Vector3(10, 0, 0))
	monde.ajouter(chose, "bloc", chose.position)

	BancP1.mettre_a_jour_occupation(monde, [_agent(Vector3(0, 0, 0))], TRANSFORMATIONS_OCCUPATION)
	verif.v(chose.proprietes.get("occupe", false), "verrou intermediaire : doit etre occupee")

	# Ce que extinction.gd:_appliquer_a_zero fait reellement a la fin d'un
	# chantier -- profil_saillance est deja absent (gele par l'occupation),
	# a_zero.retirer ne fait donc rien dessus, mais travail_restant/
	# transformation sont bien retires, inconditionnellement.
	chose.proprietes.erase("travail_restant")
	chose.proprietes.erase("transformation")

	BancP1.mettre_a_jour_occupation(monde, [_agent(Vector3(0, 0, 0))], TRANSFORMATIONS_OCCUPATION)

	verif.v(not chose.proprietes.has("occupe"), "'occupe' doit se retirer meme si le chantier est fini")
	verif.v(not chose.proprietes.has("profil_saillance"),
		"un chantier fini ne doit JAMAIS retrouver sa saillance")
	verif.v(not chose.proprietes.has("profil_saillance_gele"), "le gel doit etre nettoye, jamais laisse en suspens")

# "Aucun comptage d'agents" (voir BUT de la tache) : UN SEUL agent a
# portee_travail suffit a occuper, qu'il y en ait un ou dix autres hors
# portee -- occupe est un booleen, jamais un compte.
func _un_seul_agent_a_portee_suffit_aucun_comptage() -> void:
	var monde := Monde.new()
	var chose := _chose_chantier("bloc_1", Vector3(10, 0, 0))
	monde.ajouter(chose, "bloc", chose.position)

	BancP1.mettre_a_jour_occupation(monde, [_agent(Vector3(0, 0, 0)), _agent(Vector3(9999, 0, 0))], TRANSFORMATIONS_OCCUPATION)

	verif.v(chose.proprietes.get("occupe", false),
		"un seul agent a portee suffit a occuper -- aucun comptage d'agents necessaire")

# Chantier "engagement du colon" (PHASE 1, scripts/couplage.gd) : VERROU
# INTEGRATEUR du bug d'oscillation ferme par cette phase (voir
# docs/design.md, corps interne, entree "engagement" ;
# docs/prototypes.md banc_p1).
#
# Boucle manuelle (pas Boucle.tracer -- celle-ci n'appelle QUE
# agir_et_deplacer, jamais Extinction.avancer/mettre_a_jour_occupation ;
# ce test a besoin des trois par tick, dans le MEME ordre que
# banc_p1.gd:_process reel) : profil "bloc" local, saillance_intrinseque
# 10.0/portee_saillance 1000.0 -- calibre pour que bloc_b (distance 700
# apres convergence du colon sur bloc_a, facteur 0.3) pese une saillance
# CONSTANTE de 3.0, alors que bloc_a, une fois OCCUPE (son profil_saillance
# gele par mettre_a_jour_occupation, EXACTEMENT comme en jeu reel), tombe a
# saillance NATURELLE ZERO -- sans engagement, plus rien ne le retiendrait
# une fois bloc_b au-dessus de 0. Avec l'engagement (poids 5.0,
# data/engagements.json:colon_chantier), la reinjection de agir.gd
# (_avec_cible_engagee) le maintient a un score de 5.0 > 3.0, quel que
# soit l'avancement du chantier -- le colon place, gain_inertie=0.0 (la
# personnalite ne peut pas expliquer ce resultat), ne lache JAMAIS bloc_a
# pour bloc_b, jusqu'a la fin de la simulation.
const PROFIL_SAILLANCE_BLOC_LENT := {
	"bloc_lent": {"saillance_intrinseque": 10.0, "portee_saillance": 1000.0},
}
const TRANSFORMATIONS_BLOC_LENT := {
	"bloc_lent_transfo": {"portee_travail": 25.0},
}
const ENGAGEMENTS_COLON_CHANTIER := {
	"colon_chantier": {
		"poids": 5.0,
		"seuil_satisfait": 0.0,
		"seuil_bascule": 2.0,
		"sens_satisfaction": "sous_seuil",
		"satisfait_par": "travail_restant",
		"arrache_par": "saillance_superieure_seuil",
	},
}

func _bloc_lent(id: String, pos: Vector3) -> Dictionary:
	return {
		"id": id, "position": pos,
		"proprietes": {
			"cassable": true, "profil_saillance": "bloc_lent",
			"travail_restant": 15.0, "travail_initial": 15.0,
			"transformation": "bloc_lent_transfo",
		},
	}

func _engagement_ferme_oscillation_sur_bloc_lent() -> void:
	var monde := Monde.new()
	var bloc_a := _bloc_lent("bloc_a", Vector3.ZERO)
	var bloc_b := _bloc_lent("bloc_b", Vector3(700, 0, 0))
	monde.ajouter(bloc_a, "bloc", bloc_a.position)
	monde.ajouter(bloc_b, "bloc", bloc_b.position)

	var colon := {
		"position": Vector3(200, 0, 0),
		"proprietes": {
			"vitesse": 150.0, "canaux": ["vue"], "canaux_config": {"vue": {"portee": 1600.0}},
			"attaches": [], "forme": {"gain_inertie": 0.0},
			"poids_verbes": {"approcher": 1.0}, "engagement": null,
		},
		"action_en_cours": {},
	}
	var geste := Callable(BancP1, "agir_et_deplacer").bind(
		monde, CATALOGUE_CANAUX, {}, PROFIL_SAILLANCE_BLOC_LENT, CATALOGUE_DEFORMATIONS, {"cassable": {"verbes": ["approcher"]}},
		{}, {}, TRANSFORMATIONS_BLOC_LENT, ENGAGEMENTS_COLON_CHANTIER, 1.0)

	var jamais_devie_vers_bloc_b := true
	for i in 10:
		var agents := [{"position": colon.position, "rythme": 1.5}]
		Extinction.avancer([bloc_a, bloc_b], agents, 1.0, TRANSFORMATIONS_BLOC_LENT)
		var r: Dictionary = geste.call(colon)
		BancP1.mettre_a_jour_occupation(monde, agents, TRANSFORMATIONS_BLOC_LENT)
		if r.decision != null and r.chose != null and r.chose.id == "bloc_b":
			jamais_devie_vers_bloc_b = false

	verif.v(jamais_devie_vers_bloc_b,
		"un colon place engage sur un bloc lent ne doit JAMAIS devier vers un bloc jumeau, " +
		"meme quand l'avancement du premier tombe a presque rien")
	verif.v(colon.position.distance_to(bloc_a.position) < 1.0,
		"le colon doit rester physiquement sur bloc_a, jamais repartir vers bloc_b")
	verif.v(bloc_a.proprietes.travail_restant < 15.0,
		"bloc_a doit avoir reellement avance (le colon travaille dessus, extinction.gd consomme travail_restant)")
	verif.v(colon.proprietes.engagement != null and colon.proprietes.engagement.cible_id == "bloc_a",
		"le colon doit rester engage sur bloc_a jusqu'a la fin de la simulation")

# PHASE 2 (chantier "L'entite comme agent complet", corps physiologique --
# voir docs/cadrage_phase2_reserves.md). Charge le VRAI data/types.json,
# jamais une table locale : ce test verrouille le CONTENU reel (5 reserves
# sur le paquet "dynamique", "colon" n'en surcharge aucune), pas le
# mecanisme de fusion lui-meme -- deja verrouille sur table synthetique par
# test_objet.gd. Depuis la refonte "eclatement du corps interne", reserves
# vit dans "dynamique" (herite a plat par colon avec objet_physique/
# percevant/agent), plus dans un paquet unique "entite".
func _catalogue_types_reel() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json"))

func _colon_reel_herite_des_reserves_de_dynamique() -> void:
	var types := _catalogue_types_reel()
	var colon := BancCommun.fabriquer_colon("c1", "colon", {}, types)
	var reserves: Dictionary = colon.proprietes.get("reserves", {})
	var attendues := ["energie", "faim", "soif", "sommeil", "chaleur"]
	verif.v(reserves.size() == attendues.size(),
		"le colon reel doit porter exactement les 5 reserves du paquet dynamique, aucune surcharge en piece 1")
	for nom in attendues:
		verif.v(reserves.has(nom), "reserve '%s' absente du colon reel" % nom)
		if reserves.has(nom):
			verif.v(reserves[nom].get("reserve", 0.0) == 100.0,
				"reserve '%s' doit demarrer a 100.0 (valeur du paquet dynamique, data/types.json)" % nom)

# Verrou de bout en bout du CABLAGE reel (banc_p1.gd:_process appelle deja
# Depense.avancer sur BancCommun.objets_de(_monde), qui inclut les colons --
# voir l'en-tete de banc_p1.gd, "PHASE 2, piece 2") : le mecanisme lui-meme
# est deja prouve generique ailleurs (test_depense.gd), ce test verrouille
# que le colon reel + les donnees reelles du paquet dynamique le traversent bien.
func _reserves_du_colon_reel_decroissent_via_depense_avancer() -> void:
	var types := _catalogue_types_reel()
	var colon := BancCommun.fabriquer_colon("c1", "colon", {}, types)
	Depense.avancer([colon], 1.0, {})
	var reserves: Dictionary = colon.proprietes.reserves
	for nom in reserves:
		verif.v(absf(reserves[nom].reserve - 99.0) < 0.001,
			"reserve '%s' doit descendre de (cout_base 0.3 + surcout_action 0.7) * delta 1.0 : 100.0 -> 99.0" % nom)

# Audit couverture 2026-08-06 : _couleur_de/_couleur_reserve/
# _etiquette_decision/_faire_agir_colon/_un_feu_existe sont des fonctions
# INSTANCE (pas static, contrairement au reste de ce fichier) -- aucune
# n'etait appelee par aucun test. Instancier BancP1.new() (Node2D nu, jamais
# ajoute a l'arbre, _ready() jamais declenche) et poser a la main SEULEMENT
# les champs prives que la fonction testee lit : premiere instanciation de ce
# genre dans ce fichier, aucune modification de banc_p1.gd.

func _couleur_de_lit_le_type_pose_jamais_le_defaut() -> void:
	var b := BancP1.new()
	b._couleurs_types = {"feu": [0.9, 0.2, 0.1], "colon": [0.1, 0.5, 0.9]}
	verif.v(b._couleur_de("feu") == Color(0.9, 0.2, 0.1), "doit rendre la couleur posee pour 'feu', pas le defaut blanc")
	verif.v(b._couleur_de("colon") == Color(0.1, 0.5, 0.9), "doit distinguer deux types poses, pas retomber sur le premier")
	verif.v(b._couleur_de("inconnu") == Color(1.0, 1.0, 1.0), "un type absent du catalogue doit rendre le blanc par defaut, jamais alarmer")

func _couleur_reserve_lit_le_nom_pose_jamais_le_defaut() -> void:
	var b := BancP1.new()
	b._couleurs_reserves = {"energie": [0.2, 0.8, 0.3]}
	verif.v(b._couleur_reserve("energie") == Color(0.2, 0.8, 0.3), "doit rendre la couleur posee pour 'energie', pas le defaut")
	verif.v(b._couleur_reserve("faim") == Color(1.0, 1.0, 1.0), "une reserve absente du catalogue doit rendre le blanc par defaut")

func _etiquette_decision_cas() -> void:
	var b := BancP1.new()
	verif.v(b._etiquette_decision({"type": "irremplacable", "chose": {"id": "arbre_1"}}) == "arbre_1",
		"chose Dictionary avec id : doit rendre l'id de la chose, pas le type de la decision")
	verif.v(b._etiquette_decision({"type": "irremplacable", "chose": {}}) == "irremplacable",
		"chose Dictionary SANS id : doit retomber sur decision.type, pas planter ni rendre une chaine vide")
	verif.v(b._etiquette_decision({"type": "menace_1", "chose": "menace_2"}) == "menace_2",
		"chose non-Dictionary (String) : doit rendre la chose telle quelle, pas decision.type")
	verif.v(b._etiquette_decision({"type": "feu", "chose": null}) == "feu",
		"chose absente (null) : doit retomber sur decision.type")

# _un_feu_existe ne verifie jamais la vulnerabilite elle-meme (la cle de
# _menaces) -- seulement l'etat qu'elle pointe (ex. "brule"). Une chose
# inflammable mais pas encore brule ne doit donc pas compter.
func _un_feu_existe_distingue_inflammable_de_brule_reellement() -> void:
	var b := BancP1.new()
	b._menaces = {"inflammable": "brule"}
	b._monde = Monde.new()
	verif.v(not b._un_feu_existe(), "monde vide : aucun feu ne doit exister")

	var arbre := _ajouter(b._monde, "arbre_1", "arbre", Vector3.ZERO)
	verif.v(not b._un_feu_existe(),
		"une chose presente mais pas 'brule' ne doit pas compter comme un feu existant")

	arbre.proprietes["brule"] = true
	verif.v(b._un_feu_existe(), "une chose reellement 'brule' doit faire exister un feu")

func _faire_agir_colon_sans_feu_rend_rien_et_ne_bouge_pas() -> void:
	var b := BancP1.new()
	b._monde = Monde.new()
	b._catalogue_canaux = CATALOGUE_CANAUX
	b._menaces = {}
	b._profils_saillance = PROFILS_SAILLANCE
	b._catalogue_deformations = {}
	b._catalogue_actions = CATALOGUE_CHOSES
	var colon := {
		"id": "colon_test", "position": Vector3(0, 0, 0),
		"proprietes": {
			"vitesse": 150.0, "canaux": ["vue"], "canaux_config": {"vue": {"portee": 1600.0}},
			"attaches": [], "forme": {}, "poids_verbes": {},
		},
		"action_en_cours": {}, "action_precedente": "",
	}
	b._faire_agir_colon(colon, 0.1)
	verif.v(colon.action_precedente == "RIEN", "sans feu, l'etiquette doit etre RIEN")
	verif.v(colon.position == Vector3(0, 0, 0), "sans feu, le colon ne doit pas bouger")

func _faire_agir_colon_avec_feu_deplace_le_colon_et_redessine_le_noeud() -> void:
	var b := BancP1.new()
	b._monde = Monde.new()
	_ajouter(b._monde, "feu_1", "feu", Vector3(500, 0, 0))
	b._catalogue_canaux = CATALOGUE_CANAUX
	b._menaces = {}
	b._profils_saillance = PROFILS_SAILLANCE
	b._catalogue_deformations = {}
	b._catalogue_actions = CATALOGUE_CHOSES
	var colon := {
		"id": "colon_test", "position": Vector3(0, 0, 0),
		"proprietes": {
			"vitesse": 150.0, "canaux": ["vue"], "canaux_config": {"vue": {"portee": 1600.0}},
			"attaches": [], "forme": {}, "poids_verbes": {},
		},
		"action_en_cours": {}, "action_precedente": "",
	}
	var noeud := ColorRect.new()
	noeud.size = Vector2(24.0, 24.0)
	b._noeuds["colon_test"] = noeud

	b._faire_agir_colon(colon, 0.1)

	verif.v(colon.action_precedente != "RIEN" and colon.action_precedente.contains("feu_1"),
		"avec un feu a portee, l'etiquette doit nommer la chose visee, pas rester RIEN")
	verif.v(colon.position != Vector3(0, 0, 0), "avec un feu a portee, le colon doit s'etre deplace")
	var attendu := Vector2(colon.position.x, colon.position.y) - noeud.size / 2.0
	verif.v(noeud.position.distance_to(attendu) < 0.001,
		"le noeud de rendu doit suivre la nouvelle position du colon, centre sur son carre")
