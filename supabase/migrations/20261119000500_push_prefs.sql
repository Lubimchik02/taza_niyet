-- Язык пушей и настройки уведомлений (из «Настройки → Уведомления») — чтобы сервер их соблюдал.
alter table profiles add column locale text not null default 'ru' check (locale in ('ru', 'kk', 'en'));
alter table profiles add column notify jsonb not null default '{}';  -- {"n.chats": false, "n.quiet": true, ...}

-- Отправка пуша: Database Webhook «notifications → INSERT» вызывает функцию push (supabase/functions/push).
-- Настраивается в панели Supabase: Database → Webhooks → notifications, INSERT, тип «Supabase Edge Functions» → push.
