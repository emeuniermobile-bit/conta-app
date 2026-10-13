# Contamination

Jeu mobile où une épidémie zombie se propage dans Paris quand les joueurs se croisent.
Ce dépôt contient la **première version** décrite dans le document de conception :
prouver que la contamination passive dans Paris est amusante.

```
supabase/
  migrations/      schéma, logique de jeu (SQL), arrondissements, porteurs fantômes, tâches planifiées
  functions/
    push-dispatch/ envoi des notifications via le service Expo (Deno)
  tests/           scénarios de jeu exécutés sur un Postgres + PostGIS jetable
mobile/            appli iPhone et Android (Expo / React Native, TypeScript)
scripts/test-db.sh lance les tests de la base
```

## Ce qui est en place

| Fonction | Où |
| --- | --- |
| Inscription par numéro de téléphone, avatar simple | Supabase Auth (SMS) · `setup_profile` · écrans `sign-in`, `profile` |
| Localisation en arrière-plan | `mobile/src/lib/location.ts` (pas de GPS continu, zone de réveil quand l'appli est fermée) · `report_location` |
| Détection des rencontres côté serveur | `detect_encounters` : < 100 m pendant ≥ 2 min avec un zombie ou un fantôme |
| Porteurs fantômes | 4 trajets (lignes 1, 2, 4, tour des gares), arrêts de 6 à 18 min en station, nombre qui baisse avec les vrais zombies, interrupteur `ghosts_enabled` |
| Contamination, incubation de 3 h, transformation | `infect`, `resolve_incubations` (alerte 1 h avant) |
| Ration quotidienne, masque, antidote | `claim_daily_ration`, `craft`, `use_mask`, `use_antidote` |
| Carte de Paris par arrondissement | `get_city_map` (agrégats seulement, rien sous 3 joueurs) · onglet Paris (Apple Plans) |
| Interfaces survivant / zombie | `mobile/src/lib/theme.ts` : cyan → rouge, texte qui tremble pendant l'incubation, lettres qui se déforment côté zombie |
| Notifications d'alerte | table `notifications` → fonction Edge `push-dispatch` → service de notifications d'Expo → Apple / Google |
| Saison de 3 semaines, Laboratoire | `season_tick` : Labo à 100 %, 90 % d'infectés, ou camp majoritaire à la fin du temps ; nouvelle souche ensuite |

Pas encore fait (prévu « plus tard ») : mode Chasse en Bluetooth, vaccins et soins entre amis,
zones protégées, mutations, sabotage, missions, exploration, flash info, bilan partageable
(les données sont déjà archivées dans `season_results`), boutique.

## Fonctionnement côté serveur

Toute la logique vit dans Postgres. L'appli n'a accès à aucune table : elle appelle des
fonctions RPC qui appliquent les règles pour `auth.uid()`.

Chaque minute, pg_cron lance `game_tick()` :

1. `season_tick` — ouvre ou clôt la saison ;
2. `rebalance_ghosts` / `schedule_ghosts` — active le bon nombre de fantômes et programme leurs arrêts en station pour l'heure à venir ;
3. `detect_encounters` — croise les **présences** des survivants avec celles des zombies et fantômes ;
4. `resolve_incubations` — alerte à 1 h, transformation à 3 h ;
5. `purge_old_locations` — efface les positions de plus de 6 h.

Une **présence** est un point arrondi à 50 m (Lambert 93) avec un intervalle de temps :
de la position envoyée jusqu'à la suivante (au plus 30 min), ou la durée d'une visite iOS.
Deux présences forment une rencontre si elles sont à moins de 100 m et se recouvrent
pendant au moins 2 min. Chaque paire n'est tirée au sort qu'une fois
(probabilité `infection_probability`, réduite par un masque).

Tous les paramètres (probabilité, rayon, durée d'incubation, nombre de fantômes, objectif du
Laboratoire...) sont dans la table `game_config`, modifiable à chaud depuis le tableau de bord.

### Vie privée

- Positions arrondies à 50 m, uniquement dans Paris intra-muros, supprimées après 6 h.
- Aucune position n'est jamais renvoyée à l'appli ; le lieu d'une contamination est donné au niveau de la station ou de l'arrondissement.
- La carte n'affiche que des taux par arrondissement, et rien en dessous de 3 joueurs actifs.

## Mise en route

Tout se fait depuis un PC Windows ou Linux : pas besoin de Mac.

### 1. Serveur (Supabase)

1. Créer un projet sur [supabase.com](https://supabase.com) (offre gratuite).
2. Installer la [CLI Supabase](https://supabase.com/docs/guides/local-development/cli/getting-started), puis :

   ```sh
   supabase login
   supabase link --project-ref <ref>        # <ref> : dans l'URL du projet
   supabase db push                         # crée les tables et la logique de jeu
   supabase functions deploy push-dispatch --no-verify-jwt
   ```

3. Inventer un mot de passe pour la fonction d'envoi des notifications, puis :
   - dans *Edge Functions → Secrets*, ajouter `PUSH_DISPATCH_SECRET` avec ce mot de passe ;
   - dans *SQL Editor*, enregistrer l'adresse du projet et ce même mot de passe :

   ```sql
   select vault.create_secret('https://<ref>.supabase.co', 'project_url');
   select vault.create_secret('<mot de passe inventé>', 'push_dispatch_secret');
   ```

4. Dans *Authentication → Sign In / Providers → Phone* : activer le téléphone et brancher un fournisseur de SMS
   (Twilio propose un essai gratuit). Pour tester sans recevoir de SMS, ajouter des *numéros de test* avec un code fixe.

### 2. Appli

```sh
cd mobile
npm install
cp .env.example .env.local        # coller l'URL et la clé « anon » (Project Settings → API)
```

### Tester sur ton iPhone

**Étape A — gratuit, tout de suite : Expo Go.** Installe l'appli *Expo Go* depuis l'App Store, puis sur le PC :

```sh
cd mobile
npx expo start --go
```

(ajoute `--tunnel` si le PC et l'iPhone ne sont pas sur le même Wi-Fi). Scanne le QR code avec l'appareil photo de l'iPhone. Tu peux tester l'inscription, le profil, la carte, la ration,
la fabrication et le Laboratoire. La localisation en arrière-plan et les notifications ne marchent pas dans
Expo Go : l'appli passe en mode réduit.

**Étape B — l'appli complète : build de développement.** Il faut un compte
[Apple Developer](https://developer.apple.com/programs/) (99 €/an, obligatoire pour installer sa propre appli sur
un iPhone) et un compte [Expo](https://expo.dev) gratuit.

```sh
cd mobile
npx eas-cli@latest login
npx eas-cli@latest init                          # lie le projet à ton compte Expo
npx eas-cli@latest device:create                 # enregistre ton iPhone (lien à ouvrir sur le téléphone)
npx eas-cli@latest build --profile development --platform ios
```

EAS compile l'appli sur ses serveurs (environ 15 min), crée les certificats Apple et la clé de notifications
(réponds « oui » quand il le propose). Ouvre le lien obtenu sur l'iPhone pour installer l'appli, active le
*Mode développeur* (Réglages → Confidentialité et sécurité), puis lance `npx expo start` sur le PC et scanne
le QR code : l'appli Contamination installée s'y connecte.

**Plus tard — TestFlight** pour distribuer à des amis :
`npx eas-cli@latest build --profile production --platform ios` puis `npx eas-cli@latest submit --platform ios`.

### Tests

Les migrations et les scénarios de jeu (contamination, masque, antidote, fantômes, saisons, droits d'accès...)
tournent sur n'importe quel Postgres avec PostGIS :

```sh
PGHOST=localhost PGUSER=postgres scripts/test-db.sh
```

Côté appli : `cd mobile && npm run typecheck && npm run lint && npm test`.

La CI GitHub (`.github/workflows/ci.yml`) lance tous ces contrôles à chaque envoi de code.

## Questions ouvertes reprises du document

- Probabilité de contamination par rencontre : `game_config.infection_probability` (0,25 par défaut).
- Seuil de disparition des fantômes : `ghost_zero_at_zombies` (300 vrais zombies par défaut, décroissance linéaire depuis `ghost_max_count` = 24).
- iPhone et Android : l'appli Expo tourne sur les deux ; seul l'iPhone a été visé pour l'instant (sur Android, la carte demandera une clé Google Maps).

Données des arrondissements : [opendata.paris.fr](https://opendata.paris.fr/explore/dataset/arrondissements/), licence ODbL.
