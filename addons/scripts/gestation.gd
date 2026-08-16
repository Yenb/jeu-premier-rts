extends RefCounted

# Mecanisme du coeur : GESTATION -- troisieme phase du cycle de reproduction
# (apres stade.gd, apres accouplement.gd). Un compteur avance depuis la
# fecondation ; au franchissement d'un SEUIL (duree_gestation, catalogue), un
# flag naissance_prete est pose -- IRREVERSIBLE, jamais retire par ce fichier.
# Chantier "L'entite comme agent complet", voir docs/design.md.
#
# NE CREE JAMAIS L'ENFANT : ce fichier ne connait ni Objet.fabriquer, ni
# monde.gd, ni aucun generateur d'id -- rien dans le depot ne fabrique une
# entite de sa propre initiative (voir data/heredite.json:_note, "aucun
# concept de fabrication d'un enfant/naissance n'existe dans le depot").
# C'est A L'APPELANT (futur cablage, banc ou jeu reel) de lire
# proprietes.gestation.naissance_prete, d'appeler heredite.gd puis
# Objet.fabriquer, PUIS de retirer proprietes.gestation lui-meme -- ce
# fichier ne retire jamais rien, ne pose jamais que le flag.
#
# PROCESSUS PASSIF, HORS PIPELINE DE DECISION (meme famille que charge.gd,
# lien_personnel_croissance.gd, accouplement.gd) : jamais appele par
# agir.gd. avancer() ne depend d'aucune perception, contrairement a
# accouplement.gd -- une gestation deja posee progresse seule, qu'un
# partenaire soit encore percu ou non, encore vivant ou non.
#
# DEUX FONCTIONS :
#
# avancer(entite, catalogue, delta) -- fait progresser une gestation DEJA
# POSEE (par accouplement.gd ou par poser() ci-dessous). Rendu SILENCIEUX
# (pas une alarme) si proprietes.gestation est absent : ce fichier est
# appele sur TOUT le monde, comme charge.gd/accouplement.gd, la plupart des
# choses n'ont simplement rien a y faire. Initialise
# gestation.duree_gestation_ecoulee a 0.0 au premier appel (accouplement.gd
# ne pose pas ce champ -- voir CARTE.md), l'incremente de delta a CHAQUE
# appel, INCONDITIONNELLEMENT (meme patron que epigenetique.gd:age_marque),
# et pose gestation.naissance_prete = true des que le compteur atteint
# duree_gestation (resolu par proprietes.reproduction_ref, catalogue
# data/reproduction.json, forme A -- meme reference qui a servi a
# accouplement.gd pour poser cette gestation). IDEMPOTENT : une fois
# naissance_prete deja pose, avancer() rend la main immediatement sans
# rien recalculer -- un compteur qui continuerait de monter apres le
# signal serait sans objet (l'appelant est cense retirer gestation des
# qu'il consomme le flag) et fausserait un futur relevu de
# duree_gestation_ecoulee dans un resume LLM.
#
# poser(entite, partenaire_data, catalogue) -- POINT D'ENTREE SEPARE pour
# les modes "asexuee"/"parthenogenese", ou accouplement.gd ne tourne
# jamais (il ne s'execute que pour "sexuee", voir sa propre garde). Pose
# proprietes.gestation avec EXACTEMENT les memes quatre cles que
# accouplement.gd:_poser_gestation (partenaire_id, partenaire_genes_etat,
# partenaire_marques_epigenetiques, accouplement_tick), pour que avancer()
# et tout futur lecteur (heredite.gd) traitent une gestation posee par
# n'importe quel chemin de facon identique -- une seule forme de
# gestation dans tout le depot, jamais deux selon le mode.
#   - partenaire_data == null (mode ASEXUEE) : l'entite est sa propre
#     source -- partenaire_id devient l'id de l'entite elle-meme,
#     partenaire_genes_etat/partenaire_marques_epigenetiques sont une COPIE
#     PROFONDE de ses propres genes_etat/marques_epigenetiques courants.
#   - partenaire_data un Dictionary PARTIEL (mode PARTHENOGENESE) : toute
#     cle absente (id/genes_etat/marques_epigenetiques) retombe sur la
#     meme source que le cas asexuee (l'entite elle-meme) -- "partiel"
#     veut dire que l'appelant peut fournir UNIQUEMENT ce qui diverge
#     (un partenaire_id documentaire, par exemple) sans avoir a recopier
#     lui-meme les genes.
#   - accouplement_tick : ce fichier ne recoit AUCUN tick_actuel dans sa
#     signature (contrairement a accouplement.gd) -- il n'y a pas
#     d'evenement de perception mutuelle a horodater pour une
#     reproduction asexuee/parthenogenetique. Pose a 0 par defaut, un
#     horodatage informatif qui ne pretend PAS dater un accouplement
#     reel -- meme statut "jamais relu par ce fichier" que dans
#     accouplement.gd, jamais un mensonge puisque personne ne le lit
#     comme une vraie date.
# GARDE GESTATION (meme discipline que accouplement.gd) : une entite qui
# porte deja proprietes.gestation est ignoree d'emblee par poser() --
# rendu silencieux, jamais une alarme.
#
# Structurel vs facultatif (voir docs/design.md, "Propriete structurelle vs
# facultative") : proprietes.gestation absent est un point neutre LEGITIME
# pour avancer() (silencieux, pas une alarme -- meme contrat que
# mode_reproduction different de "sexuee" cote accouplement.gd).
# DES QU'UNE GESTATION EST PRESENTE (CAS DU COUPLE, meme precedent que
# jugement.gd:gain_jugement/plafond_jugement) : proprietes.reproduction_ref
# devient STRUCTURELLE pour avancer() -- absente, push_error, rien
# d'ecrit. Idem pour poser() : reproduction_ref est STRUCTURELLE des que
# poser() est appele (elle doit deja exister sur le type pour que
# n'importe quel mode de reproduction ait un sens). Le catalogue recu
# doit porter l'entree ref ET son champ duree_gestation -- l'un ou
# l'autre absent alarme et n'ecrit rien (jamais un defaut silencieux de
# 0.0, qui ferait naitre l'entite des le premier avancer() sans que
# personne ne l'ait voulu).
#
# entite : Dictionary { id, position, proprietes }, mute en place par
#          avancer()/poser() -- seule proprietes.gestation change.
# partenaire_data : Variant -- null (asexuee) ou Dictionary partiel
#          (parthenogenese), jamais mute, seulement lu.
# catalogue : Dictionary reproduction_ref -> { seuil_accouplement,
#          taux_montee, duree_gestation } -- data/reproduction.json, jamais
#          charge par ce fichier (meme convention que tout le corps
#          interne).
# delta : float, secondes ecoulees ce pas -- consomme uniquement par
#          l'incrementation de duree_gestation_ecoulee, en SECONDES BRUTES
#          (decision Yael : pas de conversion annees_par_seconde comme
#          senescence.gd -- duree_gestation vit directement en secondes
#          dans data/reproduction.json).
#
# Resumabilite JSON stricte (voir docs/cadrage_corps_interne_colon.md) :
# gestation ne porte que des feuilles String/Dictionary/int/float/bool
# (naissance_prete est un bool) -- aucun Vector3, aucun Callable, meme
# contrat que celui pose par accouplement.gd.

static func avancer(entite: Dictionary, catalogue: Dictionary, delta: float) -> void:
	var proprietes: Dictionary = entite.get("proprietes", {})
	if not proprietes.has("gestation"):
		return
	var gestation: Dictionary = proprietes.gestation
	if gestation.get("naissance_prete", false):
		return
	if not proprietes.has("reproduction_ref"):
		push_error("gestation.gd : propriete structurelle 'reproduction_ref' absente de proprietes (gestation en cours)")
		return
	var ref: String = proprietes.reproduction_ref
	if not catalogue.has(ref):
		push_error("gestation.gd : reproduction_ref '%s' absente du catalogue" % ref)
		return
	var regle: Dictionary = catalogue[ref]
	if not regle.has("duree_gestation"):
		push_error("gestation.gd : entree '%s' du catalogue reproduction ne porte pas 'duree_gestation'" % ref)
		return
	var duree_gestation: float = regle.duree_gestation
	if not gestation.has("duree_gestation_ecoulee"):
		gestation["duree_gestation_ecoulee"] = 0.0
	gestation["duree_gestation_ecoulee"] = gestation.duree_gestation_ecoulee + delta
	if gestation.duree_gestation_ecoulee >= duree_gestation:
		gestation["naissance_prete"] = true

static func poser(entite: Dictionary, partenaire_data, catalogue: Dictionary) -> void:
	var proprietes: Dictionary = entite.get("proprietes", {})
	if proprietes.has("gestation"):
		return
	if not proprietes.has("reproduction_ref"):
		push_error("gestation.gd : propriete structurelle 'reproduction_ref' absente de proprietes")
		return
	var ref: String = proprietes.reproduction_ref
	if not catalogue.has(ref):
		push_error("gestation.gd : reproduction_ref '%s' absente du catalogue" % ref)
		return
	var source: Dictionary = partenaire_data if partenaire_data != null else proprietes
	proprietes["gestation"] = {
		"partenaire_id": source.get("id", entite.get("id", "")),
		"partenaire_genes_etat": source.get("genes_etat", proprietes.get("genes_etat", {})).duplicate(true),
		"partenaire_marques_epigenetiques": source.get("marques_epigenetiques", proprietes.get("marques_epigenetiques", {})).duplicate(true),
		"accouplement_tick": 0,
	}
