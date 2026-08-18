extends RefCounted

const LienPersonnel = preload("res://scripts/lien_personnel.gd")
const AttacheParTrait = preload("res://scripts/attache_par_trait.gd")

# Couche 4 : agir. Transforme ce qui est visible (Dominance.visibles)
# en action. Aucun type d'action en dur : le moteur ne connait que
# des nombres, l'action est une cle lue dans le catalogue.
#
# Une saillance est un nombre et un type. D'ou elle vient (attache
# menacee, proximite, ou toute source future) ne regarde pas cette
# couche : "attache" et "menace" ne sont jamais lus ici.
#
# RESOLUTION DU VERBE (catalogue Dictionary propriete -> { verbes: [cle, ...] }),
# jamais par nom de type -- meme fermeture que attaches.gd
# (instance.type != attache.type devenu proprietes.get(attache.propriete)) :
# - origine ATTACHE (visible sans cle "chose") : visible.type porte deja
#   attache.propriete (attaches.gd) -- catalogue.get(visible.type)
#   resout directement, inchange. data/types_attaches.json migre vers la
#   forme a liste (commit 7e7891a) : ses entrees portent "verbes" comme
#   data/types_choses.json.
# - origine PROXIMITE (visible avec cle "chose", la chose percue) :
#   catalogue.get(visible.type) resolvait par NOM DE TYPE (bug ferme
#   cette session). Desormais : scan des cles du catalogue (des noms de
#   PROPRIETE, ex. "brule") contre chose.proprietes -- le premier
#   present et vrai l'emporte. Une chose sans aucune propriete du
#   catalogue est un cas LEGITIME (chose ordinaire) : action vide,
#   aucune alarme. Ordre de scan = ordre d'iteration du Dictionary
#   (ordre d'insertion, donc du JSON) : si une chose porte DEUX
#   proprietes du catalogue a la fois, la premiere rencontree gagne --
#   NON TRANCHE, aucune priorite voulue, voir CARTE.md §6.
# - UNE PROPRIETE PROPOSE PLUSIEURS VERBES (decl.verbes, Array de cles) :
#   retient celui dont colon.proprietes.poids_verbes porte le poids le
#   plus haut STRICTEMENT POSITIF (nul : pas choisi ; negatif : interdit
#   -- troisieme axe au meme rang qu'attaches/forme, jamais nesté dedans,
#   voir docs/design.md). Aucun verbe positif chez ce colon : action
#   vide, cas LEGITIME (meme contrat que "chose sans propriete
#   actionnable"), aucune alarme. Deux verbes a egalite stricte au poids
#   maximum (strictement positif) : ALARME (push_error, nommant les
#   verbes et le poids), PUIS garde l'ordre d'iteration de la liste (le
#   premier declare l'emporte) -- on ne tranche pas, on refuse le
#   silence. Meme forme que propagation.gd sur delai_propagation et
#   extinction.gd sur portee_travail : push_error, comportement actuel
#   CONSERVE. Voir CARTE.md §6.
# - AUCUNE ENTREE RESOLUE (decl == {}) : chose ou attache sans propriete
#   du catalogue -- cas LEGITIME (chose ordinaire), action vide, aucune
#   alarme.
# - ENTREE RESOLUE SANS "verbes" (decl non vide, cle "verbes" absente) :
#   catalogue malforme -- push_error nommant la propriete concernee, puis
#   action vide. Meme forme que propagation.gd sur delai_propagation et
#   extinction.gd sur portee_travail : push_error + retour neutre, jamais
#   un defaut silencieux. Plus de chemin de repli vers l'ancienne forme
#   { action: cle } : tous les catalogues du depot (types_choses.json,
#   types_attaches.json) sont a la forme a liste.
#   poids_verbes est STRUCTURELLE sur proprietes, au meme titre
#   qu'attaches/forme (absente -> push_error + retour neutre, jamais un
#   defaut silencieux) -- verifiee seulement au moment ou une entree
#   "verbes" est resolue, jamais quand decl est vide ou malforme (les
#   deux autres issues de _action, voir ci-dessus).
#   Valeur vide ({}) legitime (voir docs/design.md, "Propriete
#   structurelle vs facultative") ; chaque poids a l'interieur reste
#   FACULTATIF, defaut 0.0 (neutre).
#
# INERTIE : la tache en cours (colon.action_en_cours, forme { id,
# position, type }) recoit un bonus de saillance (forme.gain_inertie)
# avant comparaison. La comparaison se fait par ID quand action_en_cours
# en porte un (saillance de proximite : une chose precise, deux choses du
# meme type restent distinctes), par TYPE sinon (saillance d'attache :
# aucune identite, seule la valeur compte -- voir docs/design.md,
# corollaire "la saillance est une valeur, pas une appartenance"). A
# tache egale, elle gagne. Il faut une saillance strictement plus haute
# pour en sortir.
#
# ENGAGEMENT (couplage.gd, PHASE 1 du chantier "L'entite comme agent
# complet") : bonus ADDITIF de plus, apres gain_inertie, JAMAIS un
# remplacement -- gain_inertie reste une preference de PERSONNALITE,
# l'engagement est un FAIT PHYSIQUE (l'entite est SUR sa cible), les deux
# coexistent sans se confondre. colon.proprietes.engagement (pose/retire
# par couplage.gd, FACULTATIF ici -- son absence dit juste "aucun
# engagement en cours", pas une alarme) ajoute son poids au score de
# l'entree dont l'identite correspond a engagement.cible_id, par la meme
# comparaison par id que l'inertie (_identifiant).
#
# REINJECTION DE LA CIBLE ENGAGEE : une chose peut sortir de visibles sans
# qu'aucune decision n'ait change -- un chantier occupe gele son propre
# profil_saillance (voir banc_p1.gd:mettre_a_jour_occupation), la rendant
# invisible a TOUT colon, y compris celui qui travaille dessus. Sans
# reinjection, l'engagement ne pourrait jamais peser (bonus applique a une
# entree qui n'existe pas) et un chantier lent laisserait le temps a une
# alternative fraiche de gagner avant la fin -- bug d'oscillation ferme
# par ce mecanisme. _avec_cible_engagee ajoute donc a visibles, AVANT de
# noter, une entree de secours { chose, type, position, saillance: 0.0 }
# pour la cible engagee SI ELLE EST ABSENTE de visibles -- recuperee par
# id depuis monde (monde.par_id(id), duck-type : n'importe quel objet
# exposant par_id convient, jamais un import de monde.gd). Sa saillance de
# depart est 0.0 : c'est le poids de l'engagement, ajoute dans _score, qui
# porte a lui seul sa chance face aux autres candidats -- aucun double
# compte, puisqu'une chose gelee ne contribue plus rien par ailleurs.
# L'ARRACHEMENT PAR SAILLANCE (une alternative devient trop forte malgre
# l'engagement) N'EST PAS empeche ici : la comparaison de score reste
# ouverte, une saillance reelle plus haute gagne quand meme -- c'est
# voulu (voir couplage.gd). C'est au cablage de banc de detecter que la
# decision a change de cible malgre l'engagement et d'appeler
# Couplage.retirer en consequence.
#
# ACTES LIANTS (PHASE 5 etape 2/4, chantier "L'entite comme agent
# complet") : apres la resolution finale du verbe (ci-dessus), choisir()
# pose un LIEN PERSONNEL (lien_personnel.gd) sur la chose visee QUAND
# l'action resolue correspond a une entree de catalogue_actes_liants
# (data/actes_liants.json, { regle_id: { verbe, propriete_cible,
# magnitude } }) ET que la chose visee porte la propriete_cible de cette
# entree. SEULE une decision d'ORIGINE PROXIMITE/JUGEMENT (visible.has
# ("chose")) peut poser un lien -- une decision d'origine ATTACHE ne porte
# aucune identite de chose (voir attaches.gd), rien a nommer dans
# liens_personnels. EFFET DE BORD DELIBERE, decision de Yael (voir
# docs/suivi_corps_interne_entite.md, PHASE 5 etape 2) : choisir() etait
# jusqu'ici un decideur PUR, sans aucune mutation d'entite -- ce chantier
# lui donne son premier effet de bord, assume plutot que deplace vers
# extinction.gd (le mecanisme qui EXECUTE l'acte), parce que
# catalogue_actes_liants resout PAR VERBE DECIDE, pas par travail physique
# accompli -- poser() peut donc s'accumuler des la decision, avant meme
# que le colon n'atteigne portee_travail. colon.proprietes.liens_personnels
# est STRUCTURELLE (posee par lien_personnel.gd, PHASE 5 etape 1) : une
# entite non equipee alarme via LienPersonnel.poser lui-meme, jamais ici.
# catalogue_actes_liants : Dictionary = {} (defaut neutre, meme convention
# que catalogue_deformations dans proximite.gd/attaches.gd/jugement.gd) --
# catalogue vide = mecanisme INERTE, aucun appelant existant (banc_p1.gd/
# banc_feu.gd/banc_charge.gd, leurs tests, banc_commun.gd:choses_a_fuir)
# n'a besoin d'etre touche ; seul scripts/banc_lien_personnel.gd (PHASE 5
# etape 2, nouveau) le charge et le transmet reellement.
#
# ATTACHE PAR TRAIT (PHASE 5 etape 4/4 piece 2/3, L'ELARGISSEMENT, voir
# attache_par_trait.gd) : DEUXIEME EFFET DE BORD de choisir(), meme famille
# que ACTES LIANTS ci-dessus -- appele APRES _appliquer_actes_liants (un
# lien tout juste pose par CE tick compte deja pour le seuil_nombre de ce
# meme tick, aucune raison de decaler d'un cycle). AttacheParTrait.avancer
# n'est INVOQUE QUE SI catalogue_attaches_par_trait n'est pas vide -- garde
# posee ICI, pas dans attache_par_trait.gd lui-meme (qui reste inchange
# dans son contrat : liens_personnels/attaches y restent STRUCTURELLES,
# alarmees des que la cle est absente, meme a catalogue vide, verifie par
# son propre test hors domaine). Sans cette garde, tout colon qui ne porte
# pas encore liens_personnels (les colons de banc_feu.gd avant fusion
# entite, les fixtures de test_agir.gd/test_agir_proximite.gd construites a
# la main) alarmerait a CHAQUE decision, meme quand aucune regle n'est
# configuree -- meme doctrine que catalogue_actes_liants ci-dessus
# ("catalogue vide = pas de verification"), appliquee ici au point d'appel
# puisque attache_par_trait.gd, lui, verifie ses proprietes structurelles
# avant meme de regarder si le catalogue a des entrees.
# catalogue_attaches_par_trait : Dictionary = {} (data/attaches_par_trait.json),
# defaut neutre. Propage reellement par banc_p1.gd/banc_feu.gd/
# banc_charge.gd/banc_lien_personnel.gd et banc_commun.gd:choses_a_fuir --
# seul banc_deformation.gd (hors du pipeline decider/agir.gd, portee
# volontairement limitee) reste hors de ce cablage.
#
# Reçoit : visibles (Dominance.visibles), colon ({ proprietes: { forme:
# { gain_inertie }, poids_verbes: { verbe: poids }, engagement: FACULTATIF
# { cible_id, poids, ... } ou null, liens_personnels: STRUCTURELLE (voir
# ACTES LIANTS ci-dessus) }, action_en_cours : { id, position,
# type } }), catalogue (Dictionary propriete -> { verbes: [cle, ...] } --
# voir RESOLUTION DU VERBE ci-dessus), monde (expose par_id(id) -> Variant,
# utilise pour la reinjection ci-dessus ET par AttacheParTrait quand
# catalogue_attaches_par_trait n'est pas vide -- jamais dereference sinon),
# catalogue_actes_liants (voir ACTES LIANTS ci-dessus, defaut {}),
# catalogue_attaches_par_trait (voir ATTACHE PAR TRAIT ci-dessus, defaut {}).
# forme est STRUCTURELLE (sa cle absente de proprietes ->
# push_error + retour neutre null, jamais un defaut silencieux) ;
# gain_inertie en son sein reste FACULTATIF (defaut 0.0 si absent).
# poids_verbes est STRUCTURELLE au meme titre (voir ci-dessus). engagement
# reste FACULTATIF ici (voir ci-dessus) -- couplage.gd, lui, le traite en
# STRUCTUREL sur l'entite qu'il pose/avance, deux fichiers, deux
# contrats, voir couplage.gd. action_en_cours reste hors proprietes : il
# change a chaque tick, ce n'est pas un fait stable de l'objet.
# Rend : { ...visible, action: cle } de l'entree retenue (cle vide si
# aucun verbe n'a de poids strictement positif chez ce colon), ou null si
# visibles (apres reinjection) est vide.

static func choisir(
	visibles: Array,
	colon: Dictionary,
	catalogue: Dictionary,
	monde: Variant,
	catalogue_actes_liants: Dictionary = {},
	catalogue_attaches_par_trait: Dictionary = {},
) -> Variant:
	var proprietes: Dictionary = colon.get("proprietes", {})
	var engagement: Variant = proprietes.get("engagement", null)
	visibles = _avec_cible_engagee(visibles, engagement, monde)
	if visibles.is_empty():
		return null

	if not proprietes.has("forme"):
		push_error("agir.gd : propriete structurelle 'forme' absente de proprietes")
		return null
	var forme: Dictionary = proprietes.forme
	var gain: float = forme.get("gain_inertie", 0.0)
	var en_cours: Dictionary = colon.get("action_en_cours", {})

	var meilleur: Dictionary = visibles[0]
	var meilleur_score := _score(meilleur, en_cours, gain, engagement)
	for i in range(1, visibles.size()):
		var v: Dictionary = visibles[i]
		var score := _score(v, en_cours, gain, engagement)
		if score > meilleur_score:
			meilleur_score = score
			meilleur = v
	var decision := _action(meilleur, catalogue, colon)
	_appliquer_actes_liants(decision, colon, catalogue_actes_liants)
	if not catalogue_attaches_par_trait.is_empty():
		AttacheParTrait.avancer(colon, monde, catalogue_attaches_par_trait)
	return decision

static func _avec_cible_engagee(visibles: Array, engagement: Variant, monde: Variant) -> Array:
	if engagement == null:
		return visibles
	var cible_id = engagement.get("cible_id", null)
	for v in visibles:
		if _identifiant(v) == cible_id:
			return visibles
	var trouve = monde.par_id(cible_id)
	if trouve == null:
		return visibles
	var resultat: Array = visibles.duplicate()
	resultat.append({
		"chose": trouve.chose,
		"type": trouve.type,
		"position": trouve.chose.position,
		"saillance": 0.0,
	})
	return resultat

# Ce qu'il faut memoriser pour que le TICK SUIVANT retrouve la meme tache
# via _meme_tache/_identifiant -- rien de plus, MAIS action_en_cours a DEUX
# lecteurs, pas un seul : l'inertie ci-dessus (type, id -- _meme_tache/
# _identifiant ne lisent jamais position) ET le LLM lecteur-de-scene
# (docs/design.md, "action_en_cours vit hors de proprietes"), qui a besoin
# de position pour ancrer sa description ("va vers le feu, la"). Juger
# position inutile parce qu'UN lecteur (l'inertie) l'ignore casserait
# l'autre (l'ancrage LLM) -- piege deja tombe une fois, ne pas le refaire :
# voir test_agir.gd, verrou dedie. decision == null (rien de visible) -> {}.
# Sinon : "type" (toujours present sur une decision) plus "id" si
# _identifiant en trouve un (origine proximite/jugement, via
# decision.chose.id ; absent pour une origine attache, sans identite -- voir
# _identifiant) plus "position" si la decision en porte une (absente pour
# une origine attache, attaches.gd ne rend jamais de position). Ne porte ni
# saillance, ni action, ni chose : ces champs ne sont relus par aucun des
# deux lecteurs, les ecrire serait de la donnee morte (meme faute que
# action_precedente ou la mutation cendre, voir CARTE.md §6).
static func etat_courant(decision: Variant) -> Dictionary:
	if decision == null:
		return {}
	var etat: Dictionary = {"type": decision.type}
	var id = _identifiant(decision)
	if id != null:
		etat["id"] = id
	if decision.has("position"):
		etat["position"] = decision.position
	return etat

static func _score(
	visible: Dictionary,
	en_cours: Dictionary,
	gain: float,
	engagement: Variant,
) -> float:
	var score: float = visible.saillance
	if _meme_tache(visible, en_cours):
		score += gain
	if engagement != null and _identifiant(visible) == engagement.get("cible_id", null):
		score += float(engagement.get("poids", 0.0))
	return score

static func _meme_tache(visible: Dictionary, en_cours: Dictionary) -> bool:
	var id_en_cours = _identifiant(en_cours)
	if id_en_cours != null:
		return _identifiant(visible) == id_en_cours
	return visible.get("type", "") == en_cours.get("type", "")

static func _identifiant(d: Dictionary) -> Variant:
	if d.has("id"):
		return d.id
	var chose = d.get("chose", null)
	if chose is Dictionary:
		return chose.get("id", null)
	return null

static func _action(visible: Dictionary, catalogue: Dictionary, colon: Dictionary) -> Dictionary:
	var decl: Dictionary = {}
	var cle_resolue := ""
	if visible.has("chose"):
		var proprietes: Dictionary = visible.chose.proprietes
		for propriete in catalogue:
			if proprietes.get(propriete, false):
				decl = catalogue[propriete]
				cle_resolue = propriete
				break
	else:
		cle_resolue = visible.type
		decl = catalogue.get(visible.type, {})
	var action: Dictionary = visible.duplicate()
	if decl.has("verbes"):
		action["action"] = _verbe_par_poids(decl.verbes, colon)
	elif decl.is_empty():
		action["action"] = ""
	else:
		push_error("agir.gd : entree de catalogue '%s' sans cle 'verbes'" % cle_resolue)
		action["action"] = ""
	return action

# ACTES LIANTS (voir en-tete de choisir()) : une decision d'origine
# PROXIMITE/JUGEMENT (decision.has("chose")) dont le verbe RESOLU
# (decision.action) matche entree.verbe, sur une chose qui porte
# entree.propriete_cible, pose un lien personnel envers cette chose --
# une decision d'origine ATTACHE (aucune chose identifiee) ne peut jamais
# matcher, il n'y a rien a nommer. Plusieurs entrees du catalogue peuvent
# matcher a la fois (memes cles jamais en conflit, chacune pose son propre
# lien) -- pas de "break", contrairement au scan de _action ci-dessus, qui
# resout une PROPRIETE (categorie exclusive) plutot qu'un ensemble de
# regles cumulables.
static func _appliquer_actes_liants(
	decision: Dictionary,
	colon: Dictionary,
	catalogue_actes_liants: Dictionary,
) -> void:
	if not decision.has("chose"):
		return
	var proprietes_chose: Dictionary = decision.chose.proprietes
	var verbe_resolu: String = decision.get("action", "")
	for cle in catalogue_actes_liants:
		var regle: Dictionary = catalogue_actes_liants[cle]
		if regle.get("verbe", "") != verbe_resolu:
			continue
		if not proprietes_chose.get(regle.get("propriete_cible", ""), false):
			continue
		LienPersonnel.poser(colon, decision.chose.id, regle.get("magnitude", 0.0))

static func _verbe_par_poids(verbes: Array, colon: Dictionary) -> String:
	var proprietes: Dictionary = colon.get("proprietes", {})
	if not proprietes.has("poids_verbes"):
		push_error("agir.gd : propriete structurelle 'poids_verbes' absente de proprietes")
		return ""
	var poids: Dictionary = proprietes.poids_verbes
	var retenu := ""
	var meilleur_poids := 0.0
	for verbe in verbes:
		var p: float = poids.get(verbe, 0.0)
		if p > 0.0 and p > meilleur_poids:
			meilleur_poids = p
			retenu = verbe
	if meilleur_poids > 0.0:
		var a_egalite: Array = []
		for verbe2 in verbes:
			if poids.get(verbe2, 0.0) == meilleur_poids:
				a_egalite.append(verbe2)
		if a_egalite.size() > 1:
			push_error("agir.gd : verbes a egalite stricte au poids maximum (%s) : %s -- '%s' conserve (premier declare), aucun departage" % [meilleur_poids, a_egalite, retenu])
	return retenu
