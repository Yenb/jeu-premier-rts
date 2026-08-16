extends RefCounted

# Mecanisme du coeur : EPIGENETIQUE -- troisieme temporalite du corps
# interne, entre la genetique (permanente, expression.gd) et le vecu
# inter-entite (cristallise, lien_personnel.gd/attache_par_trait.gd) : une
# marque ACQUISE PAR L'EXPOSITION, qui DECROIT si l'exposition cesse, et
# sera PARTIELLEMENT TRANSMISE a l'enfant plus tard (futur heredite.gd, pas
# ici). Chantier "fondation genetique dormante", voir docs/design.md
# "L'entite comme agent complet".
#
# Modele : une entite porte une marque NOMMEE
# (proprietes.marques_epigenetiques[nom_marque] = { modulateur: float,
# age_marque: float }) -- Dictionary PLAT, jamais imbrique en source/cible
# (a la difference de deformation.gd : une marque epigenetique n'a pas deux
# registres de durabilite rapide/lent, un seul modulateur qui decroit a un
# taux fixe par marque). poser() incremente modulateur d'un montant LU AU
# CATALOGUE (modulateur_pose, PAS un parametre libre comme
# deformation.gd/lien_personnel.gd -- l'appelant ne choisit pas la
# magnitude, la donnee le fait) ; avancer() decroit modulateur par
# SOUSTRACTION FIXE (taux_decroissance * delta, patron deformation.gd, PAS
# une fraction proportionnelle -- voir correction de data/epigenetique.json,
# meme session), incremente age_marque de delta INCONDITIONNELLEMENT (meme
# si la marque disparait ce tick), et RETIRE l'entree quand modulateur
# descend sous plancher_suppression (patron lien_personnel.gd) -- sans ce
# retrait, le Dictionary grossirait indefiniment de marques residuelles
# quasi nulles. age_marque ne fait QUE s'accumuler : jamais lu par ce
# fichier, jamais remis a zero, jamais consomme par le calcul de
# decroissance -- un pur horodatage informatif, pour le resume LLM ("cette
# marque a X secondes d'age") et pour le futur heredite.gd (qui pourrait un
# jour moduler la transmission par l'age de la marque, non tranche ici).
#
# Structurel vs facultatif (voir docs/design.md, "Propriete structurelle vs
# facultative") : proprietes.marques_epigenetiques est STRUCTURELLE, meme
# convention que proprietes.liens_personnels/deformation_etat -- sa cle
# absente dit "ceci n'est pas une entite equipee pour porter une marque
# epigenetique", jamais "aucune marque". Posee sur data/types.json:dynamique
# (vide par defaut, {}), heritee par tout type qui compose ce paquet -- meme
# geste que genes_actifs/genes_etat. Sa valeur vide ({}) est legitime
# (aucune marque encore posee). Une marque absente de
# proprietes.marques_epigenetiques est un point neutre legitime (poser() la
# cree, avancer() ne l'invente jamais). CONTRAIREMENT a expression.gd (qui
# la traite en FACULTATIVE, ecrit avant qu'elle rejoigne types.json, voir sa
# propre en-tete) : ce fichier, lui, sait qu'elle existe deja partout ou
# dynamique est compose, elle est donc STRUCTURELLE ici -- deux fichiers,
# deux contrats sur la meme cle, meme precedent que
# colon.proprietes.engagement (structurelle dans couplage.gd, facultative
# dans agir.gd:_score).
#
# CONTRAT CATALOGUE DIFFERENT de deformation.gd/lien_personnel.gd : ici,
# CHAQUE MARQUE est sa propre entree de catalogue (data/epigenetique.json,
# nom_marque -> { modulateur_pose, taux_decroissance, plancher_suppression,
# cible, taux_transmission_enfant, source_environnementale }), jamais une
# entree "defaut" partagee (patron liens_personnels.json) -- parce que
# modulateur_pose/taux_decroissance different reellement d'une marque a
# l'autre (une marque de guerre ne s'installe pas au meme rythme qu'une
# marque de famine), la ou un lien personnel n'a qu'UN taux universel. Une
# marque nommee (nom_marque en parametre de poser(), ou deja presente dans
# proprietes.marques_epigenetiques pour avancer()) mais absente du catalogue
# alarme (push_error) -- meme contrat que "source" (deformation.gd) ou
# "regle_id" (couplage.gd), catalogue toujours recu en parametre, jamais
# charge par ce fichier.
#
# QUI APPELLE poser() : ce fichier ne sait pas ce qu'est un "environnement
# de guerre" -- c'est le cablage (banc, ou plus tard le jeu reel) qui
# detecte l'exposition et appelle poser() lui-meme, exactement comme
# banc_deformation.gd:avancer_colon appelle Deformation.poser apres avoir
# detecte une perception du declencheur. source_environnementale (catalogue)
# reste DOCUMENTAIRE ici -- une String libre, pas encore une reference de
# catalogue verifiable, aucun mecanisme generique de detection par
# perception n'est cable dans ce chantier (decision tranchee par Yael,
# contrairement au patron de lien_personnel_croissance.gd).
#
# _lire_chemin/_ecrire_chemin : NON DUPLIQUES ici, contrairement a
# expression.gd -- ce fichier n'ecrit jamais par chemin en points, il ecrit
# directement sur proprietes.marques_epigenetiques[nom_marque], une seule
# profondeur fixe, connue d'avance.
#
# entite : Dictionary { id, position, proprietes }, mute en place par
#          poser()/avancer().
# nom_marque : String, identifiant opaque -- ce fichier ne connait aucun nom
#              de marque reel ("exposition_gravitique", "guerre", "famine"),
#              seulement des cles, tout le vocabulaire vit en donnee
#              (data/epigenetique.json).
# catalogue : Dictionary nom_marque -> { modulateur_pose, taux_decroissance,
#             plancher_suppression, ... } -- data/epigenetique.json, jamais
#             charge par ce fichier (meme convention que deformation.gd/
#             lien_personnel.gd/couplage.gd/expression.gd).
#
# Resumabilite JSON stricte (voir docs/cadrage_corps_interne_colon.md) :
# proprietes.marques_epigenetiques ne porte jamais que des float dans ses
# feuilles (modulateur, age_marque) -- aucun Vector3, aucun Callable.

static func poser(entite: Dictionary, nom_marque: String, catalogue: Dictionary) -> void:
	var proprietes: Dictionary = entite.get("proprietes", {})
	if not proprietes.has("marques_epigenetiques"):
		push_error("epigenetique.gd : propriete structurelle 'marques_epigenetiques' absente de proprietes")
		return
	if not catalogue.has(nom_marque):
		push_error("epigenetique.gd : marque '%s' absente du catalogue" % nom_marque)
		return
	var regle: Dictionary = catalogue[nom_marque]
	var modulateur_pose: float = regle.get("modulateur_pose", 0.0)
	var marques: Dictionary = proprietes.marques_epigenetiques
	if not marques.has(nom_marque):
		marques[nom_marque] = {"modulateur": 0.0, "age_marque": 0.0}
	var canal: Dictionary = marques[nom_marque]
	canal["modulateur"] = canal.get("modulateur", 0.0) + modulateur_pose

static func avancer(entite: Dictionary, delta: float, catalogue: Dictionary) -> void:
	var proprietes: Dictionary = entite.get("proprietes", {})
	if not proprietes.has("marques_epigenetiques"):
		push_error("epigenetique.gd : propriete structurelle 'marques_epigenetiques' absente de proprietes")
		return
	var marques: Dictionary = proprietes.marques_epigenetiques
	var a_retirer: Array = []
	for nom_marque in marques:
		if not catalogue.has(nom_marque):
			push_error("epigenetique.gd : marque '%s' absente du catalogue" % nom_marque)
			continue
		var regle: Dictionary = catalogue[nom_marque]
		var taux_decroissance: float = regle.get("taux_decroissance", 0.0)
		var plancher_suppression: float = regle.get("plancher_suppression", 0.0)
		var canal: Dictionary = marques[nom_marque]
		canal["age_marque"] = canal.get("age_marque", 0.0) + delta
		canal["modulateur"] = max(0.0, canal.get("modulateur", 0.0) - taux_decroissance * delta)
		if canal["modulateur"] < plancher_suppression:
			a_retirer.append(nom_marque)
	for nom_marque in a_retirer:
		marques.erase(nom_marque)
