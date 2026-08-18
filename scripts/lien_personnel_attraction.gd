extends RefCounted

# Couche 2 (saillance) : LIEN PERSONNEL COMME SOURCE PRIMAIRE -- generateur de
# candidat de saillance, au meme titre que Proximite.evaluer/Attaches.evaluer/
# Jugement.evaluer (voir CARTE.md §2, docs/design.md "DEUX SOURCES DE
# SAILLANCE"). Troisieme fichier de la famille lien_personnel_* (avec
# lien_personnel_saillance.gd/lien_personnel_croissance.gd) qui ETEND
# lien_personnel.gd SANS JAMAIS LE MUTER -- lit proprietes.liens_personnels,
# jamais n'ecrit dessus. lien_personnel.gd lui-meme reste inchange.
#
# Role (voir docs/design.md, "Le lien personnel rend saillant CE QUI S'EN
# APPROCHE") : lien_personnel_saillance.gd AMPLIFIE un candidat qui existe
# deja pour une autre raison (profil_saillance, menace, jugement) -- il ne
# CREE jamais de candidat (garde `if not entree.has("chose"): continue`,
# voir son seul appelant, banc_lien_personnel.gd:_appliquer_bonus_lien_
# personnel). Consequence : une chose aimee SANS saillance propre (un autre
# colon sans profil_saillance, une batisse intacte jamais en feu) n'apparait
# JAMAIS dans resultats, lien personnel ou pas -- un colon ne se dirige
# jamais vers ce qu'il aime si cette chose n'est saillante par aucun autre
# moyen. Ce fichier comble ce trou : pour CHAQUE chose_id que porte
# colon.proprietes.liens_personnels, il resout la chose (monde.par_id) et
# rend un candidat de saillance { chose, type, position, saillance } -- MEME
# FORME que Proximite.evaluer/Jugement.evaluer, pour que la concatenation
# vers dominance.gd (att + prox + jugement + CECI) reste aveugle a l'origine
# d'un nombre.
#
# ADDITIF, AUCUN CAS PARTICULIER (docs/design.md, DEUX SOURCES DE SAILLANCE :
# "dominance ne distingue pas les sources ; sa propre foret pese trait PLUS
# lien, sans aucun cas particulier") : ce fichier AJOUTE TOUJOURS son entree,
# meme si la chose aimee a deja un candidat via Proximite/Jugement -- il ne
# filtre jamais les choses deja candidates. Le double compte est voulu (on
# aime plus fort ce qui est deja en jeu) et s'auto-regule par dominance.gd,
# exactement comme les deux autres sources.
#
# DISTANCE AU COLON, PAS ENTRE DEUX CHOSES -- a la difference de
# lien_personnel_saillance.gd (qui mesure la distance ENTRE la chose percue
# et la chose liee, pour amplifier ce qui s'en approche), ce fichier genere
# un candidat POUR la chose liee elle-meme : la seule distance qui a un sens
# est colon -> chose liee, meme convention que proximite.gd ("Saillance de
# proximite"). DIFFERENCE avec proximite.gd : cette distance ne vient
# JAMAIS d'une perception (perceptions n'est meme pas un parametre de ce
# fichier) -- c'est le trou que ce fichier comble, une chose aimee doit
# pouvoir devenir une cible MEME HORS DE PORTEE DE PERCEPTION. La saillance
# decroit lineairement avec la distance jusqu'a 0 a portee_attraction (meme
# forme que LienPersonnelSaillance.bonus, mais bornee depuis le colon plutot
# que depuis la chose liee) : une chose aimee infiniment loin ne doit pas
# rendre la portee de perception obsolete ni permettre une teleportation de
# l'attention.
#
# colon : Dictionary { position: Vector3, proprietes: { liens_personnels } }.
# liens_personnels est STRUCTURELLE, meme convention que lien_personnel.gd/
# lien_personnel_saillance.gd/lien_personnel_croissance.gd -- sa cle absente
# dit "ceci n'est pas une entite equipee pour porter un lien personnel",
# jamais "aucun lien" -- push_error puis [].
# monde : Variant expose par_id(id) -> { chose, type } ou null (duck-type,
# meme convention que lien_personnel_saillance.gd) -- par_id alarme deja
# lui-meme si l'id est absent (chose liee detruite depuis) : ce fichier ne
# redouble pas l'alarme, il traite une reponse null comme une chose ignoree.
# catalogue : Dictionary "defaut" -> { portee_attraction } -- data/
# liens_personnels.json, jamais charge par ce fichier (meme convention que
# lien_personnel.gd/lien_personnel_saillance.gd/lien_personnel_croissance.gd).
# portee_attraction absente de l'entree "defaut" (ou l'entree elle-meme
# absente) alarme (push_error) et rend [], meme contrat que les autres
# alarmes de catalogue de ce depot.
#
# Rend : Array de { chose, type, position, saillance } -- MEME FORME que
# Proximite.evaluer/Jugement.evaluer, une entree PAR CHOSE AIMEE RESOLUE ET
# A PORTEE. Une chose introuvable (monde.par_id -> null), hors de
# portee_attraction, ou dont la saillance calculee retombe a 0 ne produit
# RIEN, jamais une entree a saillance nulle -- meme contrat que proximite.gd/
# jugement.gd.
#
# Ne mute RIEN -- ni proprietes.liens_personnels (lecture seule), ni colon,
# ni monde. Aucun nom de contenu : ce fichier ne connait ni "colon" ni aucun
# type ou propriete du monde, seulement des cles et des nombres.

static func evaluer(colon: Dictionary, monde, catalogue: Dictionary) -> Array:
	var proprietes: Dictionary = colon.get("proprietes", {})
	if not proprietes.has("liens_personnels"):
		push_error("lien_personnel_attraction.gd : propriete structurelle 'liens_personnels' absente de proprietes")
		return []
	if not catalogue.has("defaut") or not catalogue.defaut.has("portee_attraction"):
		push_error("lien_personnel_attraction.gd : catalogue sans 'defaut.portee_attraction'")
		return []
	var portee: float = catalogue.defaut.portee_attraction
	var liens: Dictionary = proprietes.liens_personnels
	var sortie: Array = []
	for chose_id in liens:
		var wrapper = monde.par_id(chose_id)
		if wrapper == null:
			continue
		var distance: float = colon.position.distance_to(wrapper.chose.position)
		if distance >= portee:
			continue
		var force: float = liens[chose_id]
		var saillance: float = force * (1.0 - distance / portee)
		if saillance <= 0.0:
			continue
		sortie.append({
			"chose": wrapper.chose,
			"type": wrapper.type,
			"position": wrapper.chose.position,
			"saillance": saillance,
		})
	return sortie
