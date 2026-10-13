-- Tâches planifiées (pg_cron) : boucle de jeu et envoi des notifications.
--
-- L'appel à la fonction Edge push-dispatch lit deux secrets dans Vault,
-- à créer une fois par projet (voir README) :
--   select vault.create_secret('https://<ref>.supabase.co', 'project_url');
--   select vault.create_secret('<mot de passe inventé>', 'push_dispatch_secret');
-- Le même mot de passe est donné à la fonction (secret PUSH_DISPATCH_SECRET).

create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;

select cron.schedule('contamination-game-tick', '* * * * *', $$ select public.game_tick() $$);

select cron.schedule('contamination-push-dispatch', '* * * * *', $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
           || '/functions/v1/push-dispatch',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'push_dispatch_secret')),
    body := '{}'::jsonb,
    timeout_milliseconds := 30000)
  where exists (select 1 from public.notifications where sent_at is null)
$$);
