# Contamination

Jeu mobile où une épidémie zombie se propage dans Paris quand les joueurs se croisent.
Ce dépôt contient la **première version** décrite dans le document de conception :
prouver que la contamination passive dans Paris est amusante.

```
supabase/
  migrations/      schéma, logique de jeu (SQL), arrondissements, porteurs fantômes, tâches planifiées
  functions/
    push-dispatch/ envoi des notifications via APNs (Deno)
  tests/           scénarios de jeu exécutés sur un Postgres + PostGIS jetable
ios/
  project.yml      projet Xcode (XcodeGen)
  Contamination/   appli SwiftUI (iOS 17+)
scripts/test-db.sh lance les tests de la base
```

## Ce qui est en place

| Fonction | Où |
| --- | --- |
| Inscription par numéro de téléphone, avatar simple | Supabase Auth (SMS) · `setup_profile` · `AuthView`, `ProfileSetupView`, `AvatarView` |
| Localisation en arrière-plan | `LocationReporter` (changements significatifs + visites iOS, pas de GPS continu) · `report_location` |
| Détection des rencontres côté serveur | `detect_encounters` : < 100 m pendant ≥ 2 min avec un zombie ou un fantôme |
| Porteurs fantômes | 4 trajets (lignes 1, 2, 4, tour des gares), arrêts de 6 à 18 min en station, nombre qui baisse avec les vrais zombies, interrupteur `ghosts_enabled` |
| Contamination, incubation de 3 h, transformation | `infect`, `resolve_incubations` (alerte 1 h avant) |
| Ration quotidienne, masque, antidote | `claim_daily_ration`, `craft`, `use_mask`, `use_antidote` |
| Carte de Paris par arrondissement | `get_city_map` (agrégats seulement, rien sous 3 joueurs) · `CityMapView` |
| Interfaces survivant / zombie | `Theme` : cyan → rouge, texte qui tremble pendant l'incubation, lettres qui se déforment côté zombie |
| Notifications d'alerte | table `notifications` → fonction Edge `push-dispatch` → APNs |
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

### Base de données et serveur

```sh
supabase link --project-ref <ref>
supabase db push                     # applique les migrations
supabase functions deploy push-dispatch
supabase secrets set APNS_KEY_ID=... APNS_TEAM_ID=... APNS_BUNDLE_ID=fr.contamination.app \
  APNS_PRIVATE_KEY="$(cat AuthKey_XXXX.p8)"
```

Puis, dans l'éditeur SQL du projet, les deux secrets utilisés par la tâche planifiée qui appelle `push-dispatch` :

```sql
select vault.create_secret('https://<ref>.supabase.co', 'project_url');
select vault.create_secret('<clé service_role>', 'service_role_key');
```

Dans le tableau de bord : activer l'authentification par téléphone et brancher un fournisseur de SMS (Twilio...).

### Appli iPhone

```sh
brew install xcodegen
cd ios
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig   # URL et clé anon Supabase, équipe Apple
xcodegen
open Contamination.xcodeproj
```

Activer les capacités *Push Notifications* et *Background Modes → Location updates* sur l'identifiant d'appli.
Les sons `alert.caf` et `zombie.caf` référencés par les notifications sont à ajouter ; en attendant, iOS joue le son par défaut.

### Tests

Les migrations et les scénarios de jeu (contamination, masque, antidote, fantômes, saisons, droits d'accès...)
tournent sur n'importe quel Postgres avec PostGIS :

```sh
PGHOST=localhost PGUSER=postgres scripts/test-db.sh
```

La CI GitHub (`.github/workflows/backend.yml`) lance ces tests et vérifie la fonction Edge.

## Questions ouvertes reprises du document

- Probabilité de contamination par rencontre : `game_config.infection_probability` (0,25 par défaut).
- Seuil de disparition des fantômes : `ghost_zero_at_zombies` (300 vrais zombies par défaut, décroissance linéaire depuis `ghost_max_count` = 24).
- iPhone seul pour l'instant ; toute la logique étant côté serveur, une appli Android n'aurait qu'à appeler les mêmes RPC.

Données des arrondissements : [opendata.paris.fr](https://opendata.paris.fr/explore/dataset/arrondissements/), licence ODbL.
