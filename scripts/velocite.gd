extends RefCounted

# Mecanisme du coeur : DERIVATION PASSIVE d'une velocite instantanee
# (chantier « velocite — vitesse instantanee passive », audit prealable
# audit_vitesse_instantanee_prealable.md). Meme gabarit que
# quantite_matiere.gd/combustible.gd : RefCounted sans etat, une seule
# fonction static pure au sens large (elle MUTE "proprietes" en place,
# meme convention que champ.gd/charge.gd sur un Dictionary partage, mais
# ne connait ni couche, ni decision, ni loi de jeu).
#
# SIXIEME NATURE, DISTINCTE DES CINQ DEJA NOMMEES (docs/design.md,
# « Direction majeure ») : ni une lecture pure, ni une ecriture differee
# irreversible, ni un transfert continu, ni un seuil reversible, ni un
# evenement ponctuel par selection. C'est une OBSERVATION -- elle ne pose
# aucune cause, ne consomme aucune reserve, ne decide rien : elle regarde
# la difference entre deux positions deja mutees par d'AUTRES mecanismes
# et la rend lisible. Rien ne serait different dans le monde si ce
# fichier n'existait pas, sinon qu'aucun objet ne saurait sa propre
# vitesse.
#
# POURQUOI PASSIVE, JAMAIS ACTIVE (decision motivee par l'audit prealable,
# section 2) : plusieurs mecanismes du coeur peuvent muter "position" sur
# le MEME objet dans le MEME tick SANS SE CONNAITRE -- banc_champ.gd en
# est la preuve vivante : le pas volontaire (banc_commun.gd:bouger_vers,
# via banc_controle.gd) et la deviation de champ.gd s'appliquent l'un
# apres l'autre dans le meme _process, sans coordination, et champ.gd
# documente lui-meme (« AUCUNE branche if domine ») que le resultat
# EMERGE de la somme des deux. Si CHAQUE mecanisme ecrivait sa propre
# velocite, le second ecraserait celle du premier au lieu de composer
# avec elle -- meme classe de bug que l'aliasing deja rencontre et
# corrige dans ce depot (banc_commun.gd:resoudre_chantier). La derivation
# passive n'a pas ce probleme : appelee UNE SEULE FOIS en fin de tick,
# elle ne regarde que la position de DEBUT et de FIN de tick, quel que
# soit le nombre de mutations intermediaires et quel que soit le
# mecanisme qui les a produites.
#
# NE PAS CONFONDRE "velocite" ET "vitesse", deux cles differentes du depot :
# `vitesse` est un SCALAIRE de configuration (le plafond d'un deplacement
# volontaire, lu par les cablages qui bougent) ; `velocite` est le VECTEUR
# observe ici, resultat de tout ce qui s'est reellement passe ce tick. Aucune
# des deux ne se derive de l'autre.
#
# RETARD D'UN TICK INHERENT : un cablage qui lit `velocite` pendant son tick
# lit celle du tick PRECEDENT, puisque ce fichier s'appelle en DERNIER (voir
# COUT D'ADOPTION ci-dessous). Le supprimer exigerait d'ecrire la velocite au
# fil des deplacements, ce qui casserait exactement la garantie d'ECRIVAIN
# UNIQUE qui fait tenir ce fichier. Dit, jamais masque.
#
# CE FICHIER NE CONNAIT AUCUN MECANISME QUI DEPLACE : champ.gd,
# banc_commun.gd:bouger_vers/bouger_selon, et tout mecanisme futur qui
# mute "position" restent INCHANGES et ne doivent JAMAIS ecrire dans
# "velocite" -- cette cle n'a qu'UN SEUL ecrivain, ce fichier, jamais un
# second (meme discipline « un fichier, un ecrivain » que CLAUDE.md pose
# pour les chantiers paralleles, appliquee ici a une propriete).
#
# COUT D'ADOPTION, A NE PAS OUBLIER (aucun pipeline central de tick
# n'existe dans ce depot -- monde.gd n'a pas de _process, voir CARTE.md) :
# CHAQUE banc qui deplace des objets et veut leur velocite doit ajouter
# lui-meme UN appel a Velocite.avancer(monde, delta) comme DERNIER appel
# de son propre _process, APRES tous les mecanismes qui mutent position
# ce tick (champ.gd, bouger_vers/bouger_selon...). Un banc qui deplace
# des objets sans faire cet appel laisse leur "velocite" silencieusement
# inerte (jamais alarmee -- la cle est FACULTATIVE par construction, voir
# ci-dessous) : une dette d'adoption, pas une garantie automatique.
#
# Recoit : monde (Array de Dictionary { id, position (Vector3),
# proprietes }, meme forme que champ.gd/charge.gd/depense.gd -- PAS le
# Monde.gd complet, un Array nu de choses, voir banc_commun.gd:objets_de
# pour l'aplatir depuis un vrai Monde), delta (float, secondes ecoulees
# ce tick).
#
# Pour chaque chose de "monde" :
# - "position" ABSENTE : chose ignoree, silencieusement, aucune alarme --
#   ce fichier peut recevoir un "monde" plus large que les seuls objets
#   physiques deplacables (toute chose sans position n'appartient
#   simplement pas a son domaine, FACULTATIF au sens de docs/design.md).
# - "position_precedente" (Dictionary proprietes) FACULTATIVE, defaut =
#   la position COURANTE -- absente au premier tick d'un objet (jamais
#   ecrite avant), ce repli rend une velocite NULLE ce tick-la, cas
#   legitime, aucune alarme : un objet qu'on commence tout juste a suivre
#   n'a par definition subi aucun deplacement MESURE encore.
# - velocite = (position - position_precedente) / max(delta,
#   SEUIL_DELTA_MINIMAL) -- meme idiome que "plancher_distance" dans
#   champ.gd : borne le denominateur pres de zero pour eviter une
#   velocite infinie ou NaN a delta quasi nul, jamais un defaut invente
#   qui simulerait un mouvement. Ecrit proprietes.velocite (Vector3).
# - Ecrit proprietes.position_precedente = position COURANTE (valeur non
#   bornee, la vraie position de ce tick) -- prepare le tick SUIVANT,
#   jamais la valeur utilisee au denominateur ci-dessus.
#
# Rend l'Array des ids dont la velocite a REELEMENT CHANGE ce tick
# (nouvelle valeur differente de l'ancienne -- capture aussi bien un
# objet qui se met a bouger qu'un objet qui vient de s'arreter, la
# transition non nulle -> nulle EST un changement), jamais la liste de
# tous les objets traites -- meme discipline que champ.gd/charge.gd/
# extinction.gd/propagation.gd.

const SEUIL_DELTA_MINIMAL := 0.0001

static func avancer(monde: Array, delta: float) -> Array:
	var changees: Array = []
	var delta_sur: float = max(delta, SEUIL_DELTA_MINIMAL)
	for chose in monde:
		if not chose.has("position"):
			continue
		var proprietes: Dictionary = chose.proprietes
		var position: Vector3 = chose.position
		var position_precedente: Vector3 = proprietes.get("position_precedente", position)
		var velocite_avant: Vector3 = proprietes.get("velocite", Vector3.ZERO)
		var velocite: Vector3 = (position - position_precedente) / delta_sur
		proprietes["velocite"] = velocite
		proprietes["position_precedente"] = position
		if not velocite.is_equal_approx(velocite_avant):
			changees.append(chose.id)
	return changees
