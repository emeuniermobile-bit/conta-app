-- Contamination — schéma de la première version.
--
-- Toute la logique de jeu vit dans Postgres : l'appli n'écrit jamais
-- directement dans les tables, elle appelle des fonctions RPC
-- (security definer) qui appliquent les règles.

create extension if not exists postgis with schema extensions;

set search_path = public, extensions;

-- ---------------------------------------------------------------------------
-- Réglages
-- ---------------------------------------------------------------------------

-- Une seule ligne, modifiable depuis le tableau de bord Supabase.
create table public.game_config (
  id                        boolean primary key default true check (id),
  -- Rencontres
  encounter_radius_m        integer  not null default 100,
  encounter_min_seconds     integer  not null default 120,
  infection_probability     numeric  not null default 0.25 check (infection_probability between 0 and 1),
  mask_protection           numeric  not null default 0.70 check (mask_protection between 0 and 1),
  mask_duration             interval not null default interval '4 hours',
  incubation                interval not null default interval '3 hours',
  incubation_warning_before interval not null default interval '1 hour',
  -- Positions
  location_grid_m           integer  not null default 50,
  location_max_accuracy_m   integer  not null default 500,
  presence_stale_after      interval not null default interval '30 minutes',
  presence_max_duration     interval not null default interval '4 hours',
  location_retention        interval not null default interval '6 hours',
  -- Porteurs fantômes
  ghosts_enabled            boolean  not null default true,
  ghost_max_count           integer  not null default 24,
  ghost_zero_at_zombies     integer  not null default 300,
  ghost_dwell_min           interval not null default interval '6 minutes',
  ghost_dwell_max           interval not null default interval '18 minutes',
  ghost_travel_per_stop     interval not null default interval '2 minutes',
  ghost_schedule_horizon    interval not null default interval '1 hour',
  -- Saison
  season_length             interval not null default interval '21 days',
  zombie_victory_ratio      numeric  not null default 0.90,
  active_player_window      interval not null default interval '72 hours',
  lab_goal_points           integer  not null default 50000,
  -- Carte : en dessous de ce nombre de joueurs actifs, un arrondissement
  -- n'affiche pas de chiffres (on ne doit pas pouvoir deviner qui est zombie).
  map_min_players           integer  not null default 3
);
insert into public.game_config default values;

-- ---------------------------------------------------------------------------
-- Géographie
-- ---------------------------------------------------------------------------

-- Toutes les géométries sont en Lambert 93 (EPSG:2154) : distances en mètres.
create table public.arrondissements (
  code smallint primary key check (code between 1 and 20),
  name text not null,
  geom geometry(MultiPolygon, 2154) not null
);
create index on public.arrondissements using gist (geom);

-- Lieux nommés (stations, gares) : servent aux trajets des fantômes et à
-- donner un nom approximatif au lieu d'une contamination.
create table public.places (
  id   serial primary key,
  name text not null unique,
  pos  geometry(Point, 2154) not null
);
create index on public.places using gist (pos);

create or replace function public.arrondissement_label(p_code smallint)
returns text language sql immutable as $$
  select case when p_code is null then 'Paris'
              when p_code = 1 then 'Paris 1er'
              else 'Paris ' || p_code || 'e' end
$$;

-- Nom de lieu « au niveau de la station ou du quartier », jamais plus précis.
create or replace function public.place_label(p_pos geometry)
returns text language sql stable as $$
  select coalesce(
    (select p.name from public.places p
      where ST_DWithin(p.pos, p_pos, 400)
      order by p.pos <-> p_pos limit 1),
    (select public.arrondissement_label(a.code) from public.arrondissements a
      where ST_Contains(a.geom, p_pos) limit 1),
    'Paris')
$$;

-- ---------------------------------------------------------------------------
-- Saisons
-- ---------------------------------------------------------------------------

create type public.season_status as enum ('active', 'survivors_won', 'zombies_won');

create table public.seasons (
  id          serial primary key,
  strain_name text not null,
  started_at  timestamptz not null default now(),
  ends_at     timestamptz not null,
  ended_at    timestamptz,
  status      public.season_status not null default 'active',
  end_reason  text,
  lab_points  integer not null default 0
);
create unique index seasons_one_active on public.seasons ((true)) where status = 'active';

create or replace function public.current_season()
returns public.seasons language sql stable as $$
  select * from public.seasons where status = 'active' limit 1
$$;

-- ---------------------------------------------------------------------------
-- Joueurs
-- ---------------------------------------------------------------------------

create type public.player_state as enum ('survivor', 'incubating', 'zombie');

-- Un profil par compte Supabase (inscription par numéro de téléphone).
create table public.profiles (
  id                   uuid primary key references auth.users (id) on delete cascade,
  display_name         text check (char_length(display_name) between 2 and 24),
  avatar               jsonb not null default '{"mask": "classic", "color": "#2EE6D6"}',
  state                public.player_state not null default 'survivor',
  state_since          timestamptz not null default now(),
  infected_at          timestamptz,
  infected_place       text,
  transform_at         timestamptz,
  incubation_warned    boolean not null default false,
  mask_until           timestamptz,
  last_ration_day      date,
  last_seen_at         timestamptz not null default now(),
  last_arrondissement  smallint references public.arrondissements (code),
  background_location  boolean not null default false,
  push_token           text,  -- jeton Expo (ExponentPushToken[...])
  -- Compteurs de la saison en cours
  contaminations       integer not null default 0,
  cures                integer not null default 0,
  lab_contribution     integer not null default 0,
  created_at           timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id) values (new.id) on conflict do nothing;
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Bilan de chaque joueur à la fin d'une saison (pour la future carte partageable).
create table public.season_results (
  season_id      integer not null references public.seasons (id) on delete cascade,
  user_id        uuid not null references public.profiles (id) on delete cascade,
  final_state    public.player_state not null,
  contaminations integer not null,
  cures          integer not null,
  lab_contribution integer not null,
  arrondissement smallint,
  primary key (season_id, user_id)
);

-- ---------------------------------------------------------------------------
-- Inventaire et fabrication
-- ---------------------------------------------------------------------------

create table public.items (
  id          text primary key,
  name        text not null,
  kind        text not null check (kind in ('ingredient', 'craft')),
  lab_points  integer not null default 0  -- points de recherche si déposé au Laboratoire
);

insert into public.items (id, name, kind, lab_points) values
  ('tissu',    'Tissu',             'ingredient', 1),
  ('filtre',   'Filtre à charbon',  'ingredient', 2),
  ('alcool',   'Alcool médical',    'ingredient', 1),
  ('plante',   'Plante médicinale', 'ingredient', 2),
  ('reactif',  'Réactif',           'ingredient', 3),
  ('masque',   'Masque',            'craft',      0),
  ('antidote', 'Antidote',          'craft',      0);

create table public.recipes (
  item_id       text not null references public.items (id),
  ingredient_id text not null references public.items (id),
  quantity      integer not null check (quantity > 0),
  primary key (item_id, ingredient_id)
);

insert into public.recipes (item_id, ingredient_id, quantity) values
  ('masque',   'tissu',   2),
  ('masque',   'filtre',  1),
  ('antidote', 'plante',  2),
  ('antidote', 'alcool',  1),
  ('antidote', 'reactif', 1);

create table public.inventory (
  user_id  uuid not null references public.profiles (id) on delete cascade,
  item_id  text not null references public.items (id),
  quantity integer not null default 0 check (quantity >= 0),
  primary key (user_id, item_id)
);

create or replace function public.give_item(p_user uuid, p_item text, p_qty integer)
returns void language sql as $$
  insert into public.inventory (user_id, item_id, quantity) values (p_user, p_item, p_qty)
  on conflict (user_id, item_id) do update set quantity = inventory.quantity + excluded.quantity
$$;

-- Retire des objets ; lève une erreur si le joueur n'en a pas assez.
create or replace function public.take_item(p_user uuid, p_item text, p_qty integer)
returns void language plpgsql as $$
begin
  update public.inventory set quantity = quantity - p_qty
   where user_id = p_user and item_id = p_item and quantity >= p_qty;
  if not found then
    raise exception 'not_enough_items: %', p_item using errcode = 'P0001';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Porteurs fantômes
-- ---------------------------------------------------------------------------

create table public.ghost_routes (
  id    serial primary key,
  name  text not null unique,
  stops integer[] not null  -- identifiants de public.places, dans l'ordre
);

create table public.ghosts (
  id              serial primary key,
  route_id        integer not null references public.ghost_routes (id) on delete cascade,
  active          boolean not null default false,
  stop_index      integer not null default 0,     -- prochain arrêt (indice dans stops, base 0)
  direction       smallint not null default 1 check (direction in (-1, 1)),
  next_arrival_at timestamptz                      -- null : à programmer depuis maintenant
);

-- ---------------------------------------------------------------------------
-- Présences : où se trouvait (approximativement) chaque porteur, et quand.
-- Un joueur génère une présence à chaque position envoyée ; un fantôme une
-- présence par arrêt en station. Supprimées après game_config.location_retention.
-- ---------------------------------------------------------------------------

create table public.presences (
  id             bigserial primary key,
  user_id        uuid references public.profiles (id) on delete cascade,
  ghost_id       integer references public.ghosts (id) on delete cascade,
  pos            geometry(Point, 2154) not null,
  arrondissement smallint references public.arrondissements (code),
  place          text,
  valid          tstzrange not null,
  created_at     timestamptz not null default now(),
  check (num_nonnulls(user_id, ghost_id) = 1),
  check (not isempty(valid))
);
create index on public.presences using gist (pos);
create index on public.presences using gist (valid);
create index on public.presences (user_id, created_at desc);
create index on public.presences (ghost_id);

-- Chaque paire de présences n'est évaluée qu'une fois.
create table public.encounters (
  id                  bigserial primary key,
  survivor_presence   bigint not null,
  carrier_presence    bigint not null,
  survivor_id         uuid not null references public.profiles (id) on delete cascade,
  zombie_id           uuid references public.profiles (id) on delete set null,
  ghost_id            integer references public.ghosts (id) on delete set null,
  place               text not null,
  occurred_at         timestamptz not null,
  probability         numeric not null,
  infected            boolean not null,
  created_at          timestamptz not null default now(),
  unique (survivor_presence, carrier_presence)
);
create index on public.encounters (survivor_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Notifications (envoyées par la fonction Edge push-dispatch)
-- ---------------------------------------------------------------------------

create table public.notifications (
  id         bigserial primary key,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  kind       text not null,
  title      text not null,
  body       text not null,
  created_at timestamptz not null default now(),
  sent_at    timestamptz,
  error      text
);
create index notifications_pending on public.notifications (created_at) where sent_at is null;

create or replace function public.paris_time(p_at timestamptz)
returns text language sql immutable as $$
  select to_char(p_at at time zone 'Europe/Paris', 'FMHH24"h"MI')
$$;

create or replace function public.notify(p_user uuid, p_kind text, p_title text, p_body text)
returns void language sql as $$
  insert into public.notifications (user_id, kind, title, body) values (p_user, p_kind, p_title, p_body)
$$;

-- Réserve un lot de notifications à envoyer (appelée par push-dispatch avec la
-- clé service_role). Deux envois simultanés ne prennent jamais la même ligne.
create or replace function public.claim_notifications(p_limit integer default 200)
returns table (id bigint, kind text, title text, body text,
               push_token text, state public.player_state)
language sql security definer set search_path = public, extensions as $$
  with claimed as (
    update public.notifications n set sent_at = now()
     where n.id in (select id from public.notifications
                     where sent_at is null order by created_at
                     limit p_limit for update skip locked)
    returning n.id, n.user_id, n.kind, n.title, n.body)
  select c.id, c.kind, c.title, c.body, p.push_token, p.state
    from claimed c join public.profiles p on p.id = c.user_id
$$;

-- ---------------------------------------------------------------------------
-- Changements d'état
-- ---------------------------------------------------------------------------

create or replace function public.infect(p_user uuid, p_at timestamptz, p_place text)
returns void language plpgsql as $$
declare
  cfg public.game_config;
  v_transform timestamptz;
begin
  select * into cfg from public.game_config;
  v_transform := now() + cfg.incubation;
  update public.profiles
     set state = 'incubating', state_since = now(), infected_at = p_at,
         infected_place = p_place, transform_at = v_transform, incubation_warned = false
   where id = p_user and state = 'survivor';
  if found then
    perform public.notify(p_user, 'infected', 'ALERTE SANITAIRE',
      format('Infection détectée à %s, %s. Transformation dans %s h. Un antidote peut encore te sauver.',
             p_place, public.paris_time(p_at), extract(hour from cfg.incubation)::int));
  end if;
end $$;

create or replace function public.cure(p_user uuid)
returns boolean language plpgsql as $$
begin
  update public.profiles
     set state = 'survivor', state_since = now(), infected_at = null, infected_place = null,
         transform_at = null, incubation_warned = false
   where id = p_user and state = 'incubating';
  return found;
end $$;

-- ---------------------------------------------------------------------------
-- Boucle de jeu (appelée chaque minute par pg_cron)
-- ---------------------------------------------------------------------------

-- Nombre de fantômes souhaité : décroît avec le nombre de vrais zombies.
create or replace function public.ghost_target_count()
returns integer language sql stable as $$
  select case when not c.ghosts_enabled then 0
              else greatest(0, round(c.ghost_max_count *
                     (1 - least(1, z.n::numeric / greatest(c.ghost_zero_at_zombies, 1)))))::int
         end
    from public.game_config c,
         (select count(*) n from public.profiles where state = 'zombie') z
$$;

create or replace function public.rebalance_ghosts()
returns integer language plpgsql as $$
declare
  v_target integer := public.ghost_target_count();
  v_active integer;
begin
  select count(*) into v_active from public.ghosts where active;
  if v_active < v_target then
    update public.ghosts set active = true, next_arrival_at = null
     where id in (select id from public.ghosts where not active order by random() limit v_target - v_active);
  elsif v_active > v_target then
    with off as (
      update public.ghosts set active = false
       where id in (select id from public.ghosts where active order by random() limit v_active - v_target)
      returning id)
    delete from public.presences p using off where p.ghost_id = off.id and lower(p.valid) > now();
  end if;
  return v_target;
end $$;

-- Programme les arrêts en station des fantômes actifs jusqu'à l'horizon.
create or replace function public.schedule_ghosts()
returns integer language plpgsql as $$
declare
  cfg public.game_config;
  g record;
  v_stops integer[];
  v_n integer;
  v_arrival timestamptz;
  v_dwell interval;
  v_idx integer;
  v_dir smallint;
  v_count integer := 0;
begin
  select * into cfg from public.game_config;
  for g in select gh.*, r.stops from public.ghosts gh join public.ghost_routes r on r.id = gh.route_id
            where gh.active for update of gh loop
    v_stops := g.stops;
    v_n := array_length(v_stops, 1);
    v_idx := least(g.stop_index, v_n - 1);
    v_dir := g.direction;
    v_arrival := coalesce(g.next_arrival_at, now());
    -- Un fantôme réactivé après une longue pause repart de maintenant.
    if v_arrival < now() - cfg.ghost_schedule_horizon then
      v_arrival := now();
    end if;
    while v_arrival < now() + cfg.ghost_schedule_horizon loop
      v_dwell := cfg.ghost_dwell_min + random() * (cfg.ghost_dwell_max - cfg.ghost_dwell_min);
      insert into public.presences (ghost_id, pos, arrondissement, place, valid)
      select g.id, p.pos,
             (select a.code from public.arrondissements a where ST_Contains(a.geom, p.pos) limit 1),
             p.name, tstzrange(v_arrival, v_arrival + v_dwell)
        from public.places p where p.id = v_stops[v_idx + 1];
      v_count := v_count + 1;
      v_arrival := v_arrival + v_dwell + cfg.ghost_travel_per_stop;
      -- Aller-retour sur la ligne.
      if v_idx + v_dir < 0 or v_idx + v_dir >= v_n then
        v_dir := -v_dir;
      end if;
      v_idx := v_idx + v_dir;
    end loop;
    update public.ghosts set stop_index = v_idx, direction = v_dir, next_arrival_at = v_arrival
     where id = g.id;
  end loop;
  return v_count;
end $$;

-- Détecte les rencontres survivant / porteur (zombie réel ou fantôme) :
-- moins de encounter_radius_m pendant au moins encounter_min_seconds.
create or replace function public.detect_encounters()
returns integer language plpgsql as $$
declare
  cfg public.game_config;
  r record;
  v_prob numeric;
  v_infected boolean;
  v_count integer := 0;
  v_survivor_state public.player_state;
  v_zone_safe boolean;
begin
  select * into cfg from public.game_config;
  for r in
    with candidates as (
      select s.id as sid, c.id as cid, s.user_id as survivor_id,
             c.user_id as zombie_id, c.ghost_id,
             coalesce(c.place, public.place_label(s.pos)) as place,
             s.valid * c.valid
               * tstzrange(greatest(sp.state_since, coalesce(zp.state_since, '-infinity')), now()) as overlap
        from public.presences s
        join public.profiles sp on sp.id = s.user_id and sp.state = 'survivor'
        join public.presences c
          on c.id <> s.id
         and c.valid && s.valid
         and ST_DWithin(c.pos, s.pos, cfg.encounter_radius_m)
        left join public.profiles zp on zp.id = c.user_id
        left join public.ghosts g on g.id = c.ghost_id
       where s.user_id is not null
         and s.valid && tstzrange(now() - cfg.location_retention, now())
         and (zp.state = 'zombie' or g.active)
         and coalesce(c.user_id <> s.user_id, true)
         and not exists (select 1 from public.encounters e
                          where e.survivor_presence = s.id and e.carrier_presence = c.id)
    )
    select * from candidates
     where not isempty(overlap)
       and upper(overlap) - lower(overlap) >= make_interval(secs => cfg.encounter_min_seconds)
     order by survivor_id, lower(overlap)
  loop
    -- Le survivant a pu être contaminé par une rencontre précédente de cette boucle.
    select state into v_survivor_state from public.profiles where id = r.survivor_id;
    continue when v_survivor_state <> 'survivor';

    v_prob := cfg.infection_probability;
    if exists (select 1 from public.profiles where id = r.survivor_id
                and mask_until > lower(r.overlap)) then
      v_prob := v_prob * (1 - cfg.mask_protection);
    end if;
    v_infected := random() < v_prob;

    insert into public.encounters (survivor_presence, carrier_presence, survivor_id, zombie_id, ghost_id,
                                   place, occurred_at, probability, infected)
    values (r.sid, r.cid, r.survivor_id, r.zombie_id, r.ghost_id,
            r.place, lower(r.overlap), v_prob, v_infected)
    on conflict do nothing;
    continue when not found;
    v_count := v_count + 1;

    if v_infected then
      perform public.infect(r.survivor_id, lower(r.overlap), r.place);
      if r.zombie_id is not null then
        update public.profiles set contaminations = contaminations + 1 where id = r.zombie_id;
        perform public.notify(r.zombie_id, 'contaminated', 'Encore un.',
          format('Je l''ai eu. %s, %s. Il ne le sait pas encore.', r.place, public.paris_time(lower(r.overlap))));
      end if;
    end if;
  end loop;
  return v_count;
end $$;

-- Avertissements et transformations en fin d'incubation.
create or replace function public.resolve_incubations()
returns integer language plpgsql as $$
declare
  cfg public.game_config;
  r record;
  v_count integer := 0;
begin
  select * into cfg from public.game_config;

  for r in update public.profiles set incubation_warned = true
            where state = 'incubating' and not incubation_warned
              and transform_at - cfg.incubation_warning_before <= now() and transform_at > now()
           returning id, transform_at loop
    perform public.notify(r.id, 'incubation_warning', 'ALERTE SANITAIRE',
      format('Transformation prévue à %s. Fabrique un antidote maintenant.', public.paris_time(r.transform_at)));
  end loop;

  for r in update public.profiles set state = 'zombie', state_since = now(), transform_at = null
            where state = 'incubating' and transform_at <= now()
           returning id loop
    perform public.notify(r.id, 'transformed', 'Tu as faim.',
      'C''est fini. Je suis des vôtres maintenant. Il y a tant de survivants à rejoindre.');
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;

create or replace function public.purge_old_locations()
returns integer language plpgsql as $$
declare v_count integer;
begin
  delete from public.presences
   where upper(valid) < now() - (select location_retention from public.game_config)
      or created_at < now() - (select location_retention from public.game_config) - interval '1 hour';
  get diagnostics v_count = row_count;
  delete from public.notifications where created_at < now() - interval '7 days';
  return v_count;
end $$;

-- ---------------------------------------------------------------------------
-- Saisons
-- ---------------------------------------------------------------------------

create or replace function public.active_player_counts()
returns table (active integer, zombies integer, incubating integer, survivors integer)
language sql stable as $$
  select count(*)::int,
         count(*) filter (where state = 'zombie')::int,
         count(*) filter (where state = 'incubating')::int,
         count(*) filter (where state = 'survivor')::int
    from public.profiles
   where display_name is not null
     and last_seen_at > now() - (select active_player_window from public.game_config)
$$;

create or replace function public.start_season(p_strain text)
returns public.seasons language plpgsql as $$
declare
  s public.seasons;
begin
  insert into public.seasons (strain_name, ends_at)
  values (p_strain, now() + (select season_length from public.game_config))
  returning * into s;
  update public.profiles
     set state = 'survivor', state_since = now(), infected_at = null, infected_place = null,
         transform_at = null, incubation_warned = false, mask_until = null,
         contaminations = 0, cures = 0, lab_contribution = 0;
  delete from public.inventory;
  delete from public.encounters;
  update public.ghosts set active = false, next_arrival_at = null;
  delete from public.presences where ghost_id is not null;
  return s;
end $$;

create or replace function public.end_season(p_status public.season_status, p_reason text)
returns void language plpgsql as $$
declare
  s public.seasons := public.current_season();
  v_title text;
  v_body text;
begin
  if s.id is null then return; end if;
  update public.seasons set status = p_status, ended_at = now(), end_reason = p_reason where id = s.id;
  insert into public.season_results (season_id, user_id, final_state, contaminations, cures,
                                     lab_contribution, arrondissement)
  select s.id, id, state, contaminations, cures, lab_contribution, last_arrondissement
    from public.profiles where display_name is not null;

  if p_status = 'survivors_won' then
    v_title := 'REMÈDE UNIVERSEL';
    v_body := format('La souche %s est vaincue. Tout Paris est guéri. Les survivants remportent la saison.', s.strain_name);
  else
    v_title := 'PARIS EST TOMBÉE';
    v_body := format('La souche %s a submergé la ville. Les zombies remportent la saison.', s.strain_name);
  end if;
  insert into public.notifications (user_id, kind, title, body)
  select id, 'season_end', v_title, v_body from public.profiles where display_name is not null;
end $$;

-- Noms de souches pour les saisons suivantes.
create or replace function public.next_strain_name()
returns text language sql volatile as $$
  select (array['Souche Lutèce', 'Souche Bièvre', 'Souche Haussmann', 'Souche Catacombe',
                'Souche Grenelle', 'Souche Belleville', 'Souche Austerlitz'])
         [1 + ((select count(*) from public.seasons)::int % 7)]
$$;

create or replace function public.season_tick()
returns void language plpgsql as $$
declare
  cfg public.game_config;
  s public.seasons := public.current_season();
  c record;
begin
  select * into cfg from public.game_config;
  if s.id is null then
    perform public.start_season(public.next_strain_name());
    return;
  end if;
  select * into c from public.active_player_counts();

  if s.lab_points >= cfg.lab_goal_points then
    perform public.end_season('survivors_won', 'lab');
  elsif c.active >= 10 and c.zombies >= cfg.zombie_victory_ratio * c.active then
    perform public.end_season('zombies_won', 'infection');
  elsif now() >= s.ends_at then
    -- Fin du temps : le camp majoritaire l'emporte (l'incubation compte côté survivants).
    if c.zombies > c.active - c.zombies then
      perform public.end_season('zombies_won', 'timeout');
    else
      perform public.end_season('survivors_won', 'timeout');
    end if;
  else
    return;
  end if;
  perform public.start_season(public.next_strain_name());
end $$;

create or replace function public.game_tick()
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_ghosts integer;
  v_scheduled integer;
  v_encounters integer;
  v_transformed integer;
  v_purged integer;
begin
  perform public.season_tick();
  v_ghosts := public.rebalance_ghosts();
  v_scheduled := public.schedule_ghosts();
  v_encounters := public.detect_encounters();
  v_transformed := public.resolve_incubations();
  v_purged := public.purge_old_locations();
  return jsonb_build_object('ghosts', v_ghosts, 'ghost_stops', v_scheduled, 'encounters', v_encounters,
                            'transformed', v_transformed, 'purged', v_purged);
end $$;

-- ---------------------------------------------------------------------------
-- API appelée par l'appli (RPC). Toutes agissent sur auth.uid().
-- ---------------------------------------------------------------------------

create or replace function public.require_player()
returns public.profiles language plpgsql as $$
declare p public.profiles;
begin
  select * into p from public.profiles where id = auth.uid() for update;
  if p.id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  return p;
end $$;

create or replace function public.setup_profile(p_display_name text, p_avatar jsonb default null)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare p public.profiles := public.require_player();
begin
  update public.profiles
     set display_name = btrim(p_display_name),
         avatar = coalesce(p_avatar, avatar)
   where id = p.id;
end $$;

create or replace function public.register_device(p_push_token text default null,
                                                  p_background_location boolean default null)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare p public.profiles := public.require_player();
begin
  -- Un jeton appartient à un seul compte.
  update public.profiles set push_token = null where push_token = p_push_token and id <> p.id;
  update public.profiles
     set push_token = coalesce(p_push_token, push_token),
         background_location = coalesce(p_background_location, background_location)
   where id = p.id;
end $$;

-- Reçoit une position. Elle est arrondie à une grille de location_grid_m mètres
-- et n'est conservée que dans Paris intra-muros.
-- p_until : fin de présence connue (visites iOS), sinon la présence dure
-- jusqu'à la position suivante, au plus presence_stale_after.
create or replace function public.report_location(p_lat double precision, p_lng double precision,
                                                  p_accuracy double precision default null,
                                                  p_recorded_at timestamptz default null,
                                                  p_until timestamptz default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  p public.profiles := public.require_player();
  cfg public.game_config;
  v_at timestamptz := least(coalesce(p_recorded_at, now()), now());
  v_pos geometry;
  v_code smallint;
  v_until timestamptz;
begin
  select * into cfg from public.game_config;
  update public.profiles set last_seen_at = now() where id = p.id;

  if v_at < now() - cfg.location_retention then
    return jsonb_build_object('stored', false, 'reason', 'too_old');
  end if;
  if p_accuracy is not null and p_accuracy > cfg.location_max_accuracy_m then
    return jsonb_build_object('stored', false, 'reason', 'inaccurate');
  end if;

  v_pos := ST_SnapToGrid(ST_Transform(ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326), 2154),
                         cfg.location_grid_m);
  select code into v_code from public.arrondissements where ST_Contains(geom, v_pos) limit 1;
  if v_code is null then
    return jsonb_build_object('stored', false, 'reason', 'outside_zone');
  end if;

  -- La présence précédente s'arrête là où commence la nouvelle.
  update public.presences
     set valid = tstzrange(lower(valid), v_at)
   where user_id = p.id and lower(valid) < v_at and upper(valid) > v_at;

  v_until := coalesce(least(p_until, v_at + cfg.presence_max_duration), v_at + cfg.presence_stale_after);
  if v_until <= v_at then
    return jsonb_build_object('stored', false, 'reason', 'empty_range');
  end if;

  insert into public.presences (user_id, pos, arrondissement, valid)
  values (p.id, v_pos, v_code, tstzrange(v_at, v_until));
  update public.profiles set last_arrondissement = v_code where id = p.id;

  return jsonb_build_object('stored', true, 'arrondissement', v_code);
end $$;

-- Ration quotidienne : une fois par jour (heure de Paris).
create or replace function public.claim_daily_ration()
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  p public.profiles := public.require_player();
  v_today date := (now() at time zone 'Europe/Paris')::date;
  v_items jsonb := '{}';
  v_extra text;
begin
  if p.last_ration_day = v_today then
    raise exception 'ration_already_claimed' using errcode = 'P0001';
  end if;
  -- Base : de quoi fabriquer un masque, plus un bonus aléatoire de deux ingrédients.
  v_items := jsonb_build_object('tissu', 2, 'filtre', 1, 'alcool', 1, 'plante', 1);
  for i in 1..2 loop
    v_extra := (array['tissu', 'filtre', 'alcool', 'plante', 'reactif'])[1 + floor(random() * 5)::int];
    v_items := jsonb_set(v_items, array[v_extra], to_jsonb(coalesce((v_items ->> v_extra)::int, 0) + 1));
  end loop;
  perform public.give_item(p.id, key, value::int) from jsonb_each_text(v_items);
  update public.profiles set last_ration_day = v_today, last_seen_at = now() where id = p.id;
  return v_items;
end $$;

create or replace function public.craft(p_item text, p_quantity integer default 1)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare
  p public.profiles := public.require_player();
  r record;
begin
  if p_quantity < 1 or not exists (select 1 from public.recipes where item_id = p_item) then
    raise exception 'unknown_recipe' using errcode = 'P0001';
  end if;
  if p.state = 'zombie' then
    raise exception 'zombies_cannot_craft' using errcode = 'P0001';
  end if;
  for r in select * from public.recipes where item_id = p_item loop
    perform public.take_item(p.id, r.ingredient_id, r.quantity * p_quantity);
  end loop;
  perform public.give_item(p.id, p_item, p_quantity);
end $$;

create or replace function public.use_mask()
returns timestamptz language plpgsql security definer set search_path = public, extensions as $$
declare
  p public.profiles := public.require_player();
  v_until timestamptz;
begin
  if p.state <> 'survivor' then
    raise exception 'mask_useless_now' using errcode = 'P0001';
  end if;
  perform public.take_item(p.id, 'masque', 1);
  v_until := greatest(now(), coalesce(p.mask_until, now())) + (select mask_duration from public.game_config);
  update public.profiles set mask_until = v_until where id = p.id;
  return v_until;
end $$;

-- Antidote : soigne soi-même pendant l'incubation. Soigner un ami viendra avec le mode Chasse.
create or replace function public.use_antidote()
returns void language plpgsql security definer set search_path = public, extensions as $$
declare p public.profiles := public.require_player();
begin
  if p.state <> 'incubating' then
    raise exception 'not_incubating' using errcode = 'P0001';
  end if;
  perform public.take_item(p.id, 'antidote', 1);
  perform public.cure(p.id);
  perform public.notify(p.id, 'cured', 'INFECTION ENRAYÉE', 'Antidote administré. Tu es de nouveau survivant.');
end $$;

-- Dépôt d'échantillons au Laboratoire mondial.
create or replace function public.contribute_to_lab(p_item text, p_quantity integer)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  p public.profiles := public.require_player();
  s public.seasons := public.current_season();
  v_points integer;
begin
  if p.state = 'zombie' then
    raise exception 'zombies_cannot_research' using errcode = 'P0001';
  end if;
  if s.id is null then
    raise exception 'no_active_season' using errcode = 'P0001';
  end if;
  select lab_points * p_quantity into v_points from public.items
   where id = p_item and kind = 'ingredient' and lab_points > 0;
  if v_points is null or p_quantity < 1 then
    raise exception 'not_a_sample' using errcode = 'P0001';
  end if;
  perform public.take_item(p.id, p_item, p_quantity);
  update public.seasons set lab_points = lab_points + v_points where id = s.id
  returning lab_points into s.lab_points;
  update public.profiles set lab_contribution = lab_contribution + v_points where id = p.id;
  return jsonb_build_object('points', v_points, 'lab_points', s.lab_points,
                            'lab_goal', (select lab_goal_points from public.game_config));
end $$;

-- Tout ce dont l'écran principal a besoin, en un appel.
create or replace function public.get_game_state()
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  p public.profiles := public.require_player();
  s public.seasons := public.current_season();
  cfg public.game_config;
  c record;
begin
  select * into cfg from public.game_config;
  select * into c from public.active_player_counts();
  update public.profiles set last_seen_at = now() where id = p.id;
  return jsonb_build_object(
    'player', jsonb_build_object(
      'id', p.id,
      'display_name', p.display_name,
      'avatar', p.avatar,
      'state', p.state,
      'infected_at', p.infected_at,
      'infected_place', p.infected_place,
      'transform_at', p.transform_at,
      'mask_until', case when p.mask_until > now() then p.mask_until end,
      'ration_available', p.last_ration_day is distinct from (now() at time zone 'Europe/Paris')::date,
      'contaminations', p.contaminations,
      'cures', p.cures,
      'lab_contribution', p.lab_contribution,
      'arrondissement', p.last_arrondissement),
    'inventory', coalesce((select jsonb_object_agg(item_id, quantity) from public.inventory
                            where user_id = p.id and quantity > 0), '{}'),
    'season', case when s.id is not null then jsonb_build_object(
      'id', s.id,
      'strain_name', s.strain_name,
      'started_at', s.started_at,
      'ends_at', s.ends_at,
      'lab_points', s.lab_points,
      'lab_goal', cfg.lab_goal_points,
      'active_players', c.active,
      'zombies', c.zombies,
      'infection_ratio', case when c.active > 0 then round(c.zombies::numeric / c.active, 3) else 0 end) end,
    'server_time', now());
end $$;

-- Carte : agrégats par arrondissement, jamais d'individus.
create or replace function public.get_city_map()
returns table (code smallint, name text, active_players integer, infection_ratio numeric, status text)
language sql stable security definer set search_path = public, extensions as $$
  with counts as (
    select a.code, a.name,
           count(p.id)::int as active,
           count(p.id) filter (where p.state in ('zombie', 'incubating'))::int as infected
      from public.arrondissements a
      left join public.profiles p
        on p.last_arrondissement = a.code
       and p.display_name is not null
       and p.last_seen_at > now() - (select active_player_window from public.game_config)
     group by a.code, a.name
  )
  select code, name,
         case when active >= cfg.map_min_players then active end,
         case when active >= cfg.map_min_players then round(infected::numeric / active, 2) end,
         case when active < cfg.map_min_players then 'unknown'
              when infected::numeric / active >= 0.5 then 'red'
              when infected::numeric / active >= 0.2 then 'contested'
              else 'green' end
    from counts, public.game_config cfg
   order by code
$$;

create or replace function public.get_leaderboard(p_limit integer default 20)
returns table (rank bigint, display_name text, contaminations integer, is_me boolean)
language sql stable security definer set search_path = public, extensions as $$
  select rank() over (order by contaminations desc), display_name, contaminations, id = auth.uid()
    from public.profiles
   where display_name is not null and contaminations > 0
   order by contaminations desc, display_name
   limit least(p_limit, 100)
$$;

-- Dernières rencontres du joueur (sans coordonnées).
create or replace function public.get_my_encounters(p_limit integer default 20)
returns table (occurred_at timestamptz, place text, infected boolean, by_ghost boolean)
language sql stable security definer set search_path = public, extensions as $$
  select occurred_at, place, infected, ghost_id is not null
    from public.encounters where survivor_id = auth.uid()
   order by occurred_at desc limit least(p_limit, 50)
$$;

-- ---------------------------------------------------------------------------
-- Sécurité : aucune table n'est accessible directement depuis l'appli.
-- ---------------------------------------------------------------------------

alter table public.game_config     enable row level security;
alter table public.arrondissements enable row level security;
alter table public.places          enable row level security;
alter table public.seasons         enable row level security;
alter table public.profiles        enable row level security;
alter table public.season_results  enable row level security;
alter table public.items           enable row level security;
alter table public.recipes         enable row level security;
alter table public.inventory       enable row level security;
alter table public.ghost_routes    enable row level security;
alter table public.ghosts          enable row level security;
alter table public.presences       enable row level security;
alter table public.encounters      enable row level security;
alter table public.notifications   enable row level security;

-- Lecture seule de son propre profil et des données de référence.
create policy "own profile" on public.profiles for select to authenticated using (id = auth.uid());
create policy "own results" on public.season_results for select to authenticated using (user_id = auth.uid());
create policy "items readable" on public.items for select to authenticated using (true);
create policy "recipes readable" on public.recipes for select to authenticated using (true);

revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on function
  public.setup_profile(text, jsonb),
  public.register_device(text, boolean),
  public.report_location(double precision, double precision, double precision, timestamptz, timestamptz),
  public.claim_daily_ration(),
  public.craft(text, integer),
  public.use_mask(),
  public.use_antidote(),
  public.contribute_to_lab(text, integer),
  public.get_game_state(),
  public.get_city_map(),
  public.get_leaderboard(integer),
  public.get_my_encounters(integer)
to authenticated;
grant execute on function public.claim_notifications(integer) to service_role;
-- Les fonctions sans security definer appelées par celles-ci s'exécutent avec
-- les droits du propriétaire ; arrondissement_label/place_label/paris_time
-- restent utilisables en interne.
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;
