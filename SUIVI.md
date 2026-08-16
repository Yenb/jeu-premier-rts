# SUIVI

Journal de bord de la programmation du jeu. SEUL document que Claude Code
modifie au fil des sessions.

Quatre sections, jamais d'autre. FAIT : une ligne par étape terminée, la plus
récente en tête, hash de commit si applicable — sinon la date — puis quoi, en
une phrase. EN COURS : ce qui est ouvert maintenant, un tiret par point.
DÉCISIONS : les choix pris en session qui ne sont écrits ni dans `CLAUDE.md` ni
dans le code ; une décision SORT d'ici dès qu'elle est écrite ailleurs.
PROCHAINES ÉTAPES : ce qui vient après, dans l'ordre.

## FAIT

- Création de `jeu/GAME_DESIGN.md`, principes fondateurs posés
- Création du `CLAUDE.md` et du `SUIVI.md` du jeu
- Architecture LLM décidée : micro-modèle stratégie + micro-modèle discussion
  (plus tard) + agents mémoire côté code
- Modèle choisi : Llama 3.2 3B via Ollama
- Connexion LLM prouvée (`banc_llm_connexion.gd`, réponse reçue)

## EN COURS

(rien d'ouvert.)

## DÉCISIONS

- Le résumé d'état est une photo complète à chaque appel, pas d'historique
  cumulé
- Le modèle de discussion est séparé du modèle de stratégie
- Plan de repli : si la machine du joueur ne tient pas, mêmes modèles sur
  serveur, même code d'appel

## PROCHAINES ÉTAPES

1. Second banc LLM avec grammaire GBNF contrainte
2. Carré rouge (joueur) + carré violet (IA) + caméra scrollable
3. Premier Modelfile agent stratégie avec system prompt
4. Boucle complète : état → résumé → modèle → clé → action visible
