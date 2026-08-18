extends RefCounted

# Brique de boucle pour tests DYNAMIQUES (multi-ticks). Fait tourner un
# colon sur N ticks en appelant, a chaque tour, le GESTE COMPLET
# decision->mouvement d'UN banc (BancP1.agir_et_deplacer ou
# BancFeu.agir_et_deplacer), DEJA LIE par l'appelant a tout ce dont ce
# geste a besoin (monde, menaces, catalogue_actions, jugements,
# orientations, delta) -- jamais une reimplementation ici. NE CALCULE
# AUCUNE DECISION NI AUCUN MOUVEMENT : elle appelle, elle ne calcule
# jamais (voir CLAUDE.md, Regle d'etat -- "le clic ou la boucle ne fait
# que declencher, jamais calculer").
#
# Hors motif test_*.gd expres, comme verif.gd : un nom qui matcherait
# serait ramasse par lanceur.gd comme un test autonome -- sans _init() ni
# quit(), il planterait ou pendrait.
#
# DETTE FERMEE (ancienne 3e copie de l'agencement decision->mouvement,
# voir git history / CARTE.md) : tracer() ne reimplemente plus la branche
# fuite/non-fuite ni n'appelle Ciblage.viser -- ce cablage vit desormais
# UNE SEULE FOIS par banc, dans sa fonction agir_et_deplacer
# (banc_p1.gd:agir_et_deplacer, banc_feu.gd:agir_et_deplacer), que le Node
# du banc (_faire_agir_colon) appelle aussi pour le jeu reel -- meme
# chemin de code des deux cotes, jamais deux formes paralleles. tracer()
# est donc desormais formellement aveugle a CHAQUE banc (aucun nom
# "banc_p1"/"banc_feu" ici) ET a la FORME de son cablage (branche fuite,
# ordre des appels, Ciblage.viser) : si agir_et_deplacer change un jour,
# ce fichier n'a rien a savoir de ce changement.
#
# Recoit :
# - colon (Dictionary, MUTE EN PLACE par le geste -- position et
#   action_en_cours changent a chaque tick, comme en jeu).
# - ticks (int) -- nombre de tours de boucle.
# - geste (Callable : colon -> Dictionary portant au moins la cle
#   "decision" -- une agir_et_deplacer DEJA LIEE par l'appelant a
#   monde/menaces/catalogue_actions/jugements/orientations/delta
#   (banc_p1.gd/banc_feu.gd), jamais une fonction nue : sans le geste
#   complet, ni le mouvement ni la memorisation de forme.gain_inertie
#   n'ont lieu, voir agir.gd/CARTE.md §6).
#
# Rend : Array de decisions (une par tick, Variant -- Dictionary ou null),
# dans l'ordre des ticks -- extrait de geste.call(colon).decision. Ne rend
# ni resultats, ni perceptions, ni visibles : un test qui en a besoin
# relit ces champs lui-meme sur le Dictionary que geste.call() rend,
# hors de cette brique.

static func tracer(
	colon: Dictionary,
	ticks: int,
	geste: Callable,
) -> Array:
	var trace: Array = []
	for i in ticks:
		var r: Dictionary = geste.call(colon)
		trace.append(r.decision)
	return trace
