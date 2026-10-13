-- Scénarios de jeu de bout en bout. Chaque bloc lève une exception si une
-- règle n'est pas respectée. Lancé par scripts/test-db.sh.

\set QUIET on
set client_min_messages = warning;

create or replace function pg_temp.check(p_ok boolean, p_what text) returns void language plpgsql as $$
begin
  if p_ok is not true then raise exception 'ÉCHEC : %', p_what; end if;
end $$;

create or replace function pg_temp.login(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', p_user::text, false)
$$;

create or replace function pg_temp.new_player(p_name text) returns uuid language plpgsql as $$
declare v uuid;
begin
  insert into auth.users (phone) values ('+33' || floor(random() * 1e9)::text) returning id into v;
  perform pg_temp.login(v);
  perform public.setup_profile(p_name);
  return v;
end $$;

-- Position décalée de p_dx / p_dy mètres par rapport à une station.
create or replace function pg_temp.near(p_place text, p_dx double precision default 0, p_dy double precision default 0,
                                        out lat double precision, out lng double precision) language sql as $$
  select ST_Y(g), ST_X(g) from (
    select ST_Transform(ST_Translate(pos, p_dx, p_dy), 4326) g from public.places where name = p_place) s
$$;

create or replace function pg_temp.report(p_user uuid, p_place text, p_ago interval,
                                          p_dx double precision default 0, p_until interval default null)
returns jsonb language plpgsql as $$
declare l record;
begin
  perform pg_temp.login(p_user);
  select * into l from pg_temp.near(p_place, p_dx);
  return public.report_location(l.lat, l.lng, 20, now() - p_ago,
                                case when p_until is not null then now() - p_ago + p_until end);
end $$;

-- Pas de fantômes pendant les premiers scénarios, contamination certaine.
update public.game_config set ghosts_enabled = false, infection_probability = 1;

-- ---------------------------------------------------------------------------
\echo '  géographie'
select pg_temp.check((select count(*) from public.arrondissements) = 20, '20 arrondissements');
select pg_temp.check(
  (select a.code from public.arrondissements a, public.places p
    where p.name = 'Châtelet' and ST_Contains(a.geom, p.pos)) = 1, 'Châtelet est dans le 1er');
select pg_temp.check(
  (select a.code from public.arrondissements a, public.places p
    where p.name = 'Nation' and ST_Contains(a.geom, p.pos)) in (11, 12, 20), 'Nation est dans le 11e/12e/20e');
select pg_temp.check(not exists (
  select 1 from public.places p where not exists (
    select 1 from public.arrondissements a where ST_DWithin(a.geom, p.pos, 50))),
  'toutes les stations sont dans Paris intra-muros');

-- ---------------------------------------------------------------------------
\echo '  la première boucle de jeu ouvre une saison'
select public.game_tick();
select pg_temp.check((public.current_season()).id is not null, 'saison active');
select pg_temp.check((public.current_season()).ends_at > now() + interval '20 days', 'saison de 3 semaines');

-- ---------------------------------------------------------------------------
\echo '  contamination passive par un zombie réel'
create temp table t (name text primary key, id uuid);
insert into t values ('alice', pg_temp.new_player('Alice')), ('zed', pg_temp.new_player('Zed')),
                     ('bob', pg_temp.new_player('Bob')), ('carla', pg_temp.new_player('Carla'));
update public.profiles set state = 'zombie', state_since = now() - interval '1 day'
 where id = (select id from t where name = 'zed');
update public.profiles set state_since = now() - interval '1 day';

-- Zed et Alice à ~60 m l'un de l'autre à Châtelet pendant 10 minutes.
select pg_temp.report((select id from t where name = 'zed'), 'Châtelet', interval '15 minutes', 0, interval '20 minutes');
select pg_temp.report((select id from t where name = 'alice'), 'Châtelet', interval '12 minutes', 60, interval '10 minutes');
-- Bob passe 1 minute seulement à côté.
select pg_temp.report((select id from t where name = 'bob'), 'Châtelet', interval '12 minutes', -40, interval '1 minute');
-- Carla reste longtemps mais à 400 m.
select pg_temp.report((select id from t where name = 'carla'), 'Châtelet', interval '12 minutes', 400, interval '10 minutes');

select public.game_tick();

select pg_temp.check((select state from public.profiles where id = (select id from t where name = 'alice')) = 'incubating',
                     'Alice est en incubation');
select pg_temp.check((select infected_place from public.profiles where id = (select id from t where name = 'alice')) = 'Châtelet',
                     'lieu donné au niveau de la station');
select pg_temp.check((select transform_at from public.profiles where id = (select id from t where name = 'alice'))
                     between now() + interval '2 hours 59 minutes' and now() + interval '3 hours 1 minute',
                     'transformation dans 3 h');
select pg_temp.check((select state from public.profiles where id = (select id from t where name = 'bob')) = 'survivor',
                     'une rencontre de moins de 2 minutes ne compte pas');
select pg_temp.check((select state from public.profiles where id = (select id from t where name = 'carla')) = 'survivor',
                     'une rencontre à plus de 100 m ne compte pas');
select pg_temp.check((select contaminations from public.profiles where id = (select id from t where name = 'zed')) = 1,
                     'le zombie gagne un point de contamination');
select pg_temp.check(exists (select 1 from public.notifications
                              where user_id = (select id from t where name = 'alice') and kind = 'infected'
                                and body like 'Infection détectée à Châtelet, %Transformation dans 3 h%'),
                     'notification d''infection');
select pg_temp.check(exists (select 1 from public.notifications
                              where user_id = (select id from t where name = 'zed') and kind = 'contaminated'),
                     'notification au zombie');

select public.game_tick();
select pg_temp.check((select count(*) from public.encounters) = 1, 'chaque rencontre n''est jouée qu''une fois');

-- ---------------------------------------------------------------------------
\echo '  ration, fabrication et antidote'
select pg_temp.login((select id from t where name = 'alice'));
select public.claim_daily_ration();
do $$ begin
  perform public.claim_daily_ration();
  raise exception 'ÉCHEC : deuxième ration le même jour';
exception when others then
  if sqlerrm not like '%ration_already_claimed%' then raise; end if;
end $$;
select pg_temp.check((select sum(quantity) from public.inventory where user_id = (select id from t where name = 'alice')) = 7,
                     'la ration contient 7 ingrédients');
select public.craft('masque');
select pg_temp.check((select quantity from public.inventory
                       where user_id = (select id from t where name = 'alice') and item_id = 'masque') = 1, 'masque fabriqué');
do $$ begin
  perform public.give_item(auth.uid(), 'plante', 2);
  perform public.give_item(auth.uid(), 'reactif', 1);
  perform public.give_item(auth.uid(), 'alcool', 1);
end $$;
select public.craft('antidote');
select public.use_antidote();
select pg_temp.check((select state from public.profiles where id = (select id from t where name = 'alice')) = 'survivor',
                     'l''antidote soigne pendant l''incubation');
do $$ begin
  perform public.craft('masque', 50);
  raise exception 'ÉCHEC : fabrication sans ingrédients';
exception when others then
  if sqlerrm not like '%not_enough_items%' then raise; end if;
end $$;

-- ---------------------------------------------------------------------------
\echo '  le masque protège'
update public.game_config set mask_protection = 1;
select public.use_mask();
-- Nouvelle présence d'Alice, toujours à côté de Zed (le soin ne compte que pour
-- les rencontres postérieures : on le recule d'une heure).
update public.profiles set state_since = now() - interval '1 hour' where id = (select id from t where name = 'alice');
select pg_temp.report((select id from t where name = 'alice'), 'Châtelet', interval '5 minutes', 30, interval '4 minutes');
select public.game_tick();
select pg_temp.check((select state from public.profiles where id = (select id from t where name = 'alice')) = 'survivor',
                     'masqué, avec une protection de 100 %, Alice n''est pas contaminée');
select pg_temp.check((select probability from public.encounters
                       where survivor_id = (select id from t where name = 'alice') order by id desc limit 1) = 0,
                     'probabilité réduite par le masque');
update public.game_config set mask_protection = 0.7;

-- ---------------------------------------------------------------------------
\echo '  fin d''incubation et transformation'
update public.profiles set state = 'incubating', transform_at = now() + interval '30 minutes'
 where id = (select id from t where name = 'bob');
select public.game_tick();
select pg_temp.check(exists (select 1 from public.notifications
                              where user_id = (select id from t where name = 'bob') and kind = 'incubation_warning'),
                     'alerte 1 h avant la transformation');
update public.profiles set transform_at = now() - interval '1 second' where id = (select id from t where name = 'bob');
select public.game_tick();
select pg_temp.check((select state from public.profiles where id = (select id from t where name = 'bob')) = 'zombie',
                     'Bob se transforme');
select pg_temp.login((select id from t where name = 'bob'));
do $$ begin
  perform public.craft('masque');
  raise exception 'ÉCHEC : un zombie fabrique';
exception when others then
  if sqlerrm not like '%zombies_cannot_craft%' then raise; end if;
end $$;

-- Un zombie fraîchement transformé ne contamine pas avec ses positions d'avant.
select pg_temp.check(not exists (select 1 from public.encounters where zombie_id = (select id from t where name = 'bob')),
                     'pas de contamination rétroactive');

-- ---------------------------------------------------------------------------
\echo '  positions : zone de jeu, précision, conservation'
select pg_temp.login((select id from t where name = 'carla'));
select pg_temp.check((public.report_location(48.8049, 2.1204, 10) ->> 'reason') = 'outside_zone', 'Versailles hors zone');
select pg_temp.check((public.report_location(48.8584, 2.3474, 2000) ->> 'reason') = 'inaccurate', 'position imprécise ignorée');
select pg_temp.check((public.report_location(48.8584, 2.3474, 10, now() - interval '7 hours') ->> 'reason') = 'too_old',
                     'position trop ancienne ignorée');
select pg_temp.check((select bool_and(ST_X(pos)::numeric % 50 = 0 and ST_Y(pos)::numeric % 50 = 0) from public.presences
                       where user_id is not null), 'positions arrondies à 50 m');
select pg_temp.check((select count(*) from public.presences where user_id = auth.uid() and upper_inf(valid)) = 0,
                     'présences bornées dans le temps');
-- Une nouvelle position clôt la précédente.
select public.report_location(48.8584, 2.3474, 10);
select public.report_location(48.8530, 2.3690, 10);
select pg_temp.check((select count(*) from public.presences where user_id = auth.uid() and valid @> now()) = 1,
                     'une seule présence en cours');
insert into public.presences (user_id, pos, valid)
select auth.uid(), pos, tstzrange(now() - interval '8 hours', now() - interval '7 hours') from public.places limit 1;
select public.purge_old_locations();
select pg_temp.check(not exists (select 1 from public.presences where upper(valid) < now() - interval '6 hours'),
                     'positions supprimées après 6 h');

-- ---------------------------------------------------------------------------
\echo '  porteurs fantômes'
update public.profiles set state = 'survivor' where id = (select id from t where name = 'bob');
update public.profiles set state = 'survivor' where id = (select id from t where name = 'zed');
update public.game_config set ghosts_enabled = true;
select public.game_tick();
select pg_temp.check((select count(*) from public.ghosts where active) = 24, '24 fantômes actifs sans vrais zombies');
select pg_temp.check((select count(*) from public.presences where ghost_id is not null and lower(valid) > now() + interval '30 minutes') > 0,
                     'trajets programmés à l''avance');
select pg_temp.check((select bool_and(upper(valid) - lower(valid) between interval '6 minutes' and interval '18 minutes')
                        from public.presences where ghost_id is not null), 'arrêts de 6 à 18 minutes');

-- Un fantôme qui stationnait depuis 5 minutes : Carla était sur le quai.
do $$
declare v_ghost integer; v_place text;
begin
  select id into v_ghost from public.ghosts where active limit 1;
  select name into v_place from public.places where name = 'Gare du Nord';
  insert into public.presences (ghost_id, pos, place, valid)
  select v_ghost, pos, name, tstzrange(now() - interval '5 minutes', now() + interval '5 minutes')
    from public.places where name = v_place;
end $$;
update public.profiles set state_since = now() - interval '1 hour' where id = (select id from t where name = 'carla');
select pg_temp.report((select id from t where name = 'carla'), 'Gare du Nord', interval '4 minutes', 20);
select public.game_tick();
select pg_temp.check((select state from public.profiles where id = (select id from t where name = 'carla')) = 'incubating',
                     'un fantôme contamine comme un vrai zombie');
select pg_temp.check((select ghost_id is not null and place = 'Gare du Nord' from public.encounters
                       where survivor_id = (select id from t where name = 'carla')), 'rencontre attribuée au fantôme');

update public.game_config set ghost_zero_at_zombies = 4;
update public.profiles set state = 'zombie' where id in (select id from t where name in ('bob', 'zed'));
select public.game_tick();
select pg_temp.check((select count(*) from public.ghosts where active) = 12, 'moitié moins de fantômes avec 2 zombies sur 4');
update public.game_config set ghosts_enabled = false;
select public.game_tick();
select pg_temp.check((select count(*) from public.ghosts where active) = 0, 'interrupteur des fantômes');
select pg_temp.check(not exists (select 1 from public.presences where ghost_id is not null and lower(valid) > now()),
                     'trajets futurs annulés');

-- ---------------------------------------------------------------------------
\echo '  carte et classement'
select pg_temp.check((select status from public.get_city_map() where code = 20) = 'unknown',
                     'moins de 3 joueurs : pas de chiffres');
update public.profiles set last_arrondissement = 1;
select pg_temp.check((select status from public.get_city_map() where code = 1) = 'red',
                     '1er : 3 infectés sur 4, zone rouge');
select pg_temp.check((select display_name from public.get_leaderboard() limit 1) = 'Zed', 'classement des contaminateurs');

-- ---------------------------------------------------------------------------
\echo '  droits d''accès depuis l''appli'
select pg_temp.login((select id from t where name = 'alice'));
set role authenticated;
select pg_temp.check((select count(*) from public.presences) = 0, 'positions invisibles');
select pg_temp.check((select count(*) from public.profiles) = 1, 'seul son propre profil est lisible');
select pg_temp.check((public.get_game_state() -> 'player' ->> 'display_name') = 'Alice', 'get_game_state');
do $$ begin
  perform public.game_tick();
  raise exception 'ÉCHEC : game_tick appelable par un joueur';
exception when insufficient_privilege then null;
end $$;
do $$ begin
  update public.profiles set state = 'survivor';
  if found then raise exception 'ÉCHEC : profil modifiable directement'; end if;
exception when insufficient_privilege then null;
end $$;
reset role;

-- ---------------------------------------------------------------------------
\echo '  Laboratoire et fin de saison'
update public.game_config set lab_goal_points = 10;
update public.profiles set state = 'survivor' where id = (select id from t where name = 'alice');
select pg_temp.login((select id from t where name = 'alice'));
select public.give_item(auth.uid(), 'reactif', 4);
select pg_temp.check((public.contribute_to_lab('reactif', 4) ->> 'lab_points')::int = 12, '4 réactifs = 12 points');
select pg_temp.check((select lab_contribution from public.profiles where id = auth.uid()) = 12, 'contribution du joueur');
select (public.current_season()).id as old_season \gset
select public.game_tick();
select pg_temp.check((select status from public.seasons where id = :old_season) = 'survivors_won',
                     'le Laboratoire à 100 % fait gagner les survivants');
select pg_temp.check((public.current_season()).id > :old_season, 'une nouvelle saison commence');
select pg_temp.check((select bool_and(state = 'survivor' and contaminations = 0) from public.profiles),
                     'tout le monde redevient survivant');
select pg_temp.check((select count(*) from public.season_results where season_id = :old_season) = 4, 'bilan archivé');
select pg_temp.check((select count(*) from public.notifications where kind = 'season_end') = 4, 'annonce de fin de saison');

\echo '  fin du temps : le camp majoritaire gagne'
update public.seasons set ends_at = now() - interval '1 second' where status = 'active';
update public.profiles set state = 'zombie' where id in (select id from t where name in ('bob', 'zed', 'carla'));
select (public.current_season()).id as old_season \gset
select public.game_tick();
select pg_temp.check((select status from public.seasons where id = :old_season) = 'zombies_won', 'majorité zombie');

-- ---------------------------------------------------------------------------
\echo '  réservation des notifications'
select pg_temp.login((select id from t where name = 'alice'));
select public.register_device('ExponentPushToken[abc]', true);
select pg_temp.login((select id from t where name = 'bob'));
select public.register_device('ExponentPushToken[abc]');
select pg_temp.check((select count(*) from public.profiles where push_token = 'ExponentPushToken[abc]') = 1,
                     'un jeton appartient à un seul compte');
select public.register_device(null, false);
select pg_temp.check((select push_token from public.profiles where id = auth.uid()) = 'ExponentPushToken[abc]',
                     'mettre à jour la localisation ne perd pas le jeton');
select pg_temp.check((select count(*) from public.claim_notifications(1000)) > 0, 'lot réservé');
select pg_temp.check((select count(*) from public.claim_notifications(1000)) = 0, 'jamais envoyées deux fois');
