# Contamination — appli mobile (Expo)

Appli iPhone (et Android) écrite avec [Expo](https://expo.dev) / React Native en TypeScript.
Aucun Mac n'est nécessaire : l'appli iPhone est compilée dans le cloud par EAS.

```
src/
  app/                 écrans (Expo Router) : connexion, profil, localisation, onglets du jeu
    (tabs)/            Statut · Paris (carte) · Labo · Classement
  components/          texte qui se corrompt, panneaux, boutons, avatar, fond radar
  lib/
    api.ts             appels au serveur (fonctions RPC Supabase)
    location.ts        localisation en arrière-plan + zone de réveil
    push.ts            notifications
    game.ts, theme.ts  règles d'affichage et thème survivant → zombie (testés)
  state/               état du jeu et thème partagés
assets/data/arrondissements.json   contours des 20 arrondissements
```

## Commandes

```sh
npm install
cp .env.example .env.local     # URL et clé « anon » du projet Supabase
npx expo start                 # serveur de développement
npm run typecheck && npm run lint && npm test
```

## Tester sur un iPhone sans Mac

Voir le [README principal](../README.md#tester-sur-ton-iphone).

## Localisation en arrière-plan

- Appli ouverte ou en arrière-plan : mises à jour « Balanced » (Wi-Fi et antennes, ~100 m), regroupées, en pause quand on ne bouge pas.
- Appli fermée : iOS ne suit plus, mais relance l'appli quand on sort d'une zone de 250 m autour de la dernière position (geofencing). L'appli envoie alors la nouvelle position et réarme une zone autour.
- Sans la permission « Toujours » : mode réduit, la position n'est envoyée qu'appli ouverte.
