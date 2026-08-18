extends RefCounted

# Mecanisme du coeur : CROISSANCE DU LIEN PERSONNEL PAR PERCEPTION -- fait
# MONTER proprietes.liens_personnels (lien_personnel.gd) depuis des
# PERCEPTIONS filtrees par trait, sur le modele exact de
# lien_personnel_saillance.gd : meme famille de fichiers qui ETENDENT
# lien_personnel.gd sans jamais le muter. lien_personnel_saillance.gd LIT
# les liens pour la saillance ; celui-ci ECRIT les liens depuis la
# perception -- lien_personnel.gd reste l'unique proprietaire de la
# decroissance/du retrait sous plancher (avancer()), aucune duplication ici.
#
# Role (voir docs/design.md, "Les collectifs n'existent pas" -- premiere
# brique du VECU INTER-ENTITE : un lien personnel peut naitre de la
# perception REPETEE d'une autre entite portant un trait recherche, pas
# seulement d'un evenement liant comme la defense d'un ouvrage
# (data/actes_liants.json, agir.gd) -- meme geste que
# banc_convergence_attache.gd:_avancer_tick_pour_colons (LienPersonnel.poser
# appele directement depuis une perception, sans decision), desormais
# generalise en mecanisme du coeur reutilisable par tout futur chantier du
# vecu inter-entite (contagion culturelle, factions par convergence,
# sedimentation).
#
# CONVENTION D'UNITE (CORRIGEE, session ulterieure a la construction du
# mecanisme -- BUG AUDITE ET FERME) : un montant fixe PAR EVENEMENT DE POSE,
# JAMAIS un debit multiplie par delta. Premiere version : `taux_montee *
# delta` -- a un framerate reel (~0.0167s/tick), le montant pose (~0.0008)
# tombait TOUJOURS sous liens_personnels.json:defaut.plancher_suppression
# (0.01), donc lien_personnel.gd:avancer (decroissance, appelee juste apres
# dans le meme tick) effacait le lien avant qu'il ait pu survivre d'un tick
# a l'autre -- cree puis detruit a chaque frame, indefiniment, aucune
# cristallisation possible. Les deux AUTRES appelants de LienPersonnel.poser
# du depot (banc_convergence_attache.gd, magnitude_exposition 0.02 ;
# agir.gd:_appliquer_actes_liants, data/actes_liants.json:magnitude 0.15)
# posent deja un montant FIXE PAR TICK QUALIFIANT, jamais mis a l'echelle du
# delta -- data/liens_personnels.json:defaut.plancher_suppression (0.01,
# catalogue partage, jamais modifie ici) est calibre pour cette convention.
# CORRIGE en alignant ce fichier sur elle : `montant_par_pose` (le champ
# s'appelait `taux_montee`, renomme pour ne plus suggerer un debit).
#
# COOLDOWN (ajoute pour la meme correction, decision Yael) : poser un montant
# fixe A CHAQUE TICK (comme les deux autres appelants) accumule trop vite a
# un framerate reel pour rester OBSERVABLE -- tout montant qui survit au
# plancher (donc > 0.01) accumule au minimum ~0.6/seconde a 60 FPS,
# cristallisant en ~1-2s, un eclair impossible a suivre a l'oeil pour une
# mise en scene de contagion culturelle voulue lente et visible (voir
# docs/prototypes.md, banc_vecu_inter_colon). `intervalle_pose` (secondes)
# espace les evenements de pose : un accumulateur de temps
# (proprietes.lien_personnel_croissance_cooldown, FACULTATIF -- voir
# structurel/facultatif plus bas) monte de `delta` a CHAQUE appel ; des qu'il
# atteint `intervalle_pose`, UN pose() est tente pour chaque (chose percue,
# trait) qui matche CE tick-la, et le reliquat (jamais remis a zero net, pour
# ne pas driver si intervalle_pose n'est pas un multiple exact des deltas
# reels) est conserve. `intervalle_pose` absent ou 0.0 degenere en "pose a
# chaque tick" (comportement des deux autres appelants) -- point neutre
# legitime, jamais une alarme.
#
# Modele : une entite porte une reference SCALAIRE
# (proprietes.lien_personnel_croissance_ref, Forme A -- meme patron que
# profil_saillance/transformation/seuils_ref/materiau, verifiee par
# scripts/test_lint_donnees.gd) vers une entree du catalogue recu en
# parametre. L'entree declare CE QUE cette entite cherche a percevoir chez
# les autres (traits_recherches, Array de String -- noms de propriete
# PLATE, jamais une attache imbriquee), COMBIEN par evenement de pose
# (montant_par_pose), A QUEL RYTHME (intervalle_pose, secondes entre deux
# poses) et JUSQU'OU (plafond, borne individuelle -- voir plus bas).
#
# PLAFOND BORNE COTE APPELANT, JAMAIS DANS lien_personnel.gd (contrainte du
# chantier : lien_personnel.gd reste pur, aucune modification) :
# LienPersonnel.poser() n'a et n'aura aucune notion de plafond -- il
# accumule sans borne, c'est son contrat depuis PHASE 5 etape 1. A chaque
# pose, ce fichier lit la force DEJA accumulee via
# LienPersonnel.force(colon, chose_id, catalogue_liens) et ne pose que le
# reliquat manquant jusqu'au plafond (jamais un montant qui le
# depasserait) -- un lien deja au plafond ne recoit plus rien, meme si le
# trait continue d'etre percu. catalogue_liens (data/liens_personnels.json)
# n'est donc PAS transmis ici pour portee_menace (ca, c'est le contrat de
# lien_personnel_saillance.gd, sans rapport avec ce fichier) : il sert
# uniquement a satisfaire la signature de LienPersonnel.force(), qui
# l'accepte sans le lire.
#
# entite (colon) : Dictionary { proprietes: { liens_personnels,
#   lien_personnel_croissance_ref, lien_personnel_croissance_cooldown } },
#   mute en place (liens_personnels via LienPersonnel.poser -- jamais
#   d'ecriture directe ; lien_personnel_croissance_cooldown ECRIT
#   DIRECTEMENT ici, seul etat propre a ce fichier).
# perceptions : Array de { chose, ... } tel que rendu par
#   perception.gd:percevoir -- seul "chose" (id + proprietes) est lu, le
#   reste (type/position/distance/canaux) est ignore.
# catalogue : Dictionary lien_personnel_croissance_ref -> { traits_recherches:
#   Array de String, montant_par_pose: float, intervalle_pose: float,
#   plafond: float } -- data/lien_personnel_croissance.json, jamais charge
#   par ce fichier (meme convention que lien_personnel.gd/deformation.gd/
#   couplage.gd).
# catalogue_liens : Dictionary "defaut" -> { ... } -- data/liens_personnels.json,
#   transmis tel quel a LienPersonnel.force() (voir PLAFOND ci-dessus).
# delta : float, secondes ecoulees ce pas -- consomme UNIQUEMENT par le
#   cooldown (plus par un debit de croissance, voir CONVENTION D'UNITE
#   ci-dessus).
#
# Structurel vs facultatif (voir docs/design.md, "Propriete structurelle vs
# facultative") : proprietes.liens_personnels ET
# proprietes.lien_personnel_croissance_ref sont STRUCTURELLES, chacune
# verifiee independamment -- meme precedent que
# lien_personnel.gd/attache_par_trait.gd (la fonction recoit une seule
# entite, jamais un monde: Array a scanner). Leur absence alarme
# (push_error) et rend sans rien ecrire. Une reference presente mais
# absente du catalogue alarme aussi (push_error nommant la reference) --
# l'entite est alors IGNOREE ce tick, jamais un repli sur une regle
# devinee. proprietes.lien_personnel_croissance_cooldown est FACULTATIVE
# (contrairement aux deux precedentes) : son absence dit juste "aucun
# evenement de pose encore ecoule", point neutre legitime (test applicable :
# une entite qui ne la porte pas encore reste, par definition, un exemplaire
# valide de ce que ce mecanisme traite) -- jamais une alarme, `.get(...,
# 0.0)` suffit.
#
# Ne mute rien d'autre que proprietes.liens_personnels (via
# LienPersonnel.poser) et proprietes.lien_personnel_croissance_cooldown
# (ecriture directe, seul etat propre a ce fichier).
#
# Resumabilite JSON stricte (voir docs/cadrage_corps_interne_colon.md) :
# lien_personnel_croissance_cooldown est un float nu -- aucun Vector3,
# aucun Callable -- survit identique a un aller-retour
# JSON.stringify/parse_string, comme le reste de proprietes.

const LienPersonnel = preload("res://scripts/lien_personnel.gd")

static func avancer(
	colon: Dictionary,
	perceptions: Array,
	catalogue: Dictionary,
	catalogue_liens: Dictionary,
	delta: float,
) -> void:
	var proprietes: Dictionary = colon.get("proprietes", {})
	if not proprietes.has("liens_personnels"):
		push_error("lien_personnel_croissance.gd : propriete structurelle 'liens_personnels' absente de proprietes")
		return
	if not proprietes.has("lien_personnel_croissance_ref"):
		push_error("lien_personnel_croissance.gd : propriete structurelle 'lien_personnel_croissance_ref' absente de proprietes")
		return
	var ref: String = proprietes.lien_personnel_croissance_ref
	if not catalogue.has(ref):
		push_error("lien_personnel_croissance.gd : lien_personnel_croissance_ref '%s' absente du catalogue" % ref)
		return
	var regle: Dictionary = catalogue[ref]
	var traits_recherches: Array = regle.get("traits_recherches", [])
	var montant_par_pose: float = regle.get("montant_par_pose", 0.0)
	var intervalle_pose: float = regle.get("intervalle_pose", 0.0)
	var plafond: float = regle.get("plafond", 0.0)

	var cooldown: float = proprietes.get("lien_personnel_croissance_cooldown", 0.0) + delta
	if cooldown < intervalle_pose:
		proprietes["lien_personnel_croissance_cooldown"] = cooldown
		return
	proprietes["lien_personnel_croissance_cooldown"] = cooldown - intervalle_pose

	for entree in perceptions:
		var chose: Dictionary = entree.chose
		for trait_recherche in traits_recherches:
			if not chose.proprietes.get(trait_recherche, false):
				continue
			var force_actuelle: float = LienPersonnel.force(colon, chose.id, catalogue_liens)
			var montant: float = min(montant_par_pose, plafond - force_actuelle)
			if montant > 0.0:
				LienPersonnel.poser(colon, chose.id, montant)
