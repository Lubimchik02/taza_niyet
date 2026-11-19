-- Taza Niyet — схема базы данных (этап 12).
-- Принципы: всё личное закрыто RLS; часы и баллы начисляет только сервер (функции ниже);
-- подтверждённые часы — неизменяемый журнал (credits), при удалении аккаунта остаются без имени.

create extension if not exists pg_trgm;
create extension if not exists pgcrypto;

-- ---------- Типы ----------
create type membership_status as enum ('pending', 'active', 'rejected', 'left');
create type org_role as enum ('volunteer', 'senior', 'coordinator');
create type difficulty as enum ('easy', 'medium', 'hard');
create type quest_status as enum ('draft', 'published', 'cancelled');
create type signup_status as enum ('joined', 'waitlist', 'cancelled');
create type report_status as enum ('sent', 'approved', 'rejected');
create type credit_kind as enum ('shift', 'senior_bonus', 'penalty');
create type hours_visibility as enum ('everyone', 'friends', 'only_me');
create type who_can_add as enum ('everyone', 'my_org', 'nobody');
create type chat_kind as enum ('team', 'direct', 'channel');
create type friend_status as enum ('pending', 'accepted');
create type report_reason as enum ('spam', 'insult', 'inappropriate', 'danger', 'other');

-- ---------- Люди ----------
create table profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  name text not null check (char_length(name) between 2 and 40),
  birth_year int not null check (birth_year between 1920 and 2020),
  city text not null default 'astana',
  visibility hours_visibility not null default 'everyone',
  show_in_search boolean not null default true,
  show_in_rating boolean not null default true,
  who_can_add who_can_add not null default 'everyone',
  -- Согласие на обработку персональных данных (Закон РК «О персональных данных»): когда и какая версия текста.
  consent_at timestamptz not null default now(),
  consent_version text not null default '2026-11',
  deletion_requested_at timestamptz,
  created_at timestamptz not null default now()
);
create index profiles_name_trgm on profiles using gin (lower(name) gin_trgm_ops);

-- ---------- Организации ----------
create table organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  type text not null,
  city text not null,
  lat double precision not null,
  lng double precision not null,
  verified boolean not null default false,
  accepts_new boolean not null default true,
  invite_code text unique check (invite_code ~ '^[A-Z0-9]{4,12}$'),
  created_at timestamptz not null default now()
);

create table memberships (
  user_id uuid not null references profiles (id) on delete cascade,
  org_id uuid not null references organizations (id) on delete cascade,
  status membership_status not null default 'pending',
  role org_role not null default 'volunteer',
  created_at timestamptz not null default now(),
  decided_at timestamptz,
  primary key (user_id, org_id)
);
-- Одна организация одновременно (заявка или членство).
create unique index memberships_one_current on memberships (user_id) where status in ('pending', 'active');

-- ---------- Квесты и команды ----------
create table quests (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations (id) on delete cascade,
  title text not null check (char_length(title) between 3 and 80),
  description text not null default '' check (char_length(description) <= 2000),
  difficulty difficulty not null default 'easy',
  starts_at timestamptz not null,
  duration_min int not null check (duration_min between 30 and 720),
  lat double precision not null,
  lng double precision not null,
  address text not null default '',
  capacity int not null check (capacity between 1 and 500),
  status quest_status not null default 'published',
  created_by uuid references profiles (id) on delete set null,
  created_at timestamptz not null default now()
);
create index quests_org_time on quests (org_id, starts_at);

create table teams (
  id uuid primary key default gen_random_uuid(),
  quest_id uuid not null references quests (id) on delete cascade,
  number int not null,
  senior_id uuid references profiles (id) on delete set null,
  capacity int not null check (capacity between 1 and 50),
  unique (quest_id, number)
);

create table signups (
  id uuid primary key default gen_random_uuid(),
  quest_id uuid not null references quests (id) on delete cascade,
  team_id uuid references teams (id) on delete set null,
  user_id uuid not null references profiles (id) on delete cascade,
  status signup_status not null,
  waitlist_pos int,
  created_at timestamptz not null default now(),
  cancelled_at timestamptz,
  check ((status = 'waitlist') = (waitlist_pos is not null))
);
create unique index signups_one_per_quest on signups (quest_id, user_id) where status <> 'cancelled';
create index signups_team on signups (team_id) where status = 'joined';

-- ---------- Смена ----------
create table check_ins (
  signup_id uuid primary key references signups (id) on delete cascade,
  at timestamptz not null,                 -- время отметки на телефоне (может прийти позже из очереди)
  received_at timestamptz not null default now(),
  lat double precision,
  lng double precision,
  distance_m int,
  geo_verified boolean not null default false,
  marked_by uuid references profiles (id) on delete set null  -- не null — отметил старший вручную
);

create table shift_reports (
  id uuid primary key default gen_random_uuid(),
  quest_id uuid not null references quests (id) on delete cascade,
  team_id uuid not null unique references teams (id) on delete cascade,
  senior_id uuid references profiles (id) on delete set null,
  status report_status not null default 'sent',
  submitted_at timestamptz not null default now(),
  decided_by uuid references profiles (id) on delete set null,
  decided_at timestamptz,
  note text
);

create table shift_report_items (
  report_id uuid not null references shift_reports (id) on delete cascade,
  user_id uuid not null references profiles (id) on delete cascade,
  present boolean not null,
  hours numeric(3, 1) not null check (hours >= 0 and hours * 2 = round(hours * 2)),
  manual boolean not null default false,   -- отмечен старшим без геометки — координатор видит отдельно
  primary key (report_id, user_id)
);

-- Журнал начислений. Только вставка из функций; user_id обнуляется при удалении аккаунта.
create table credits (
  id bigint generated always as identity primary key,
  user_id uuid references profiles (id) on delete set null,
  org_id uuid references organizations (id) on delete set null,
  quest_id uuid references quests (id) on delete set null,
  report_id uuid references shift_reports (id) on delete set null,
  kind credit_kind not null,
  hours numeric(4, 1) not null default 0,
  tz int not null,
  quest_title text not null,     -- копия на момент начисления: портфолио не меняется задним числом
  org_name text not null,
  shift_date date not null,
  created_at timestamptz not null default now()
);
create index credits_user on credits (user_id, created_at desc);

-- ---------- Друзья и блокировки ----------
create table friendships (
  user_a uuid not null references profiles (id) on delete cascade,
  user_b uuid not null references profiles (id) on delete cascade,
  requested_by uuid not null references profiles (id) on delete cascade,
  status friend_status not null default 'pending',
  created_at timestamptz not null default now(),
  primary key (user_a, user_b),
  check (user_a < user_b)
);

create table blocks (
  blocker uuid not null references profiles (id) on delete cascade,
  blocked uuid not null references profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker, blocked)
);

-- ---------- Чаты ----------
create table chats (
  id uuid primary key default gen_random_uuid(),
  kind chat_kind not null,
  org_id uuid references organizations (id) on delete cascade,
  team_id uuid unique references teams (id) on delete cascade,
  direct_key text unique,         -- «uuid1:uuid2» для личных
  created_at timestamptz not null default now()
);

create table chat_members (
  chat_id uuid not null references chats (id) on delete cascade,
  user_id uuid not null references profiles (id) on delete cascade,
  muted boolean not null default false,
  last_read_at timestamptz not null default now(),
  primary key (chat_id, user_id)
);

create table messages (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references chats (id) on delete cascade,
  author_id uuid references profiles (id) on delete set null,
  body text not null check (char_length(body) between 1 and 2000),
  client_id text,                 -- id из телефона: повтор из офлайн-очереди не создаёт дубль
  created_at timestamptz not null default now(),
  unique (author_id, client_id)
);
create index messages_chat_time on messages (chat_id, created_at desc);

create table abuse_reports (
  id bigint generated always as identity primary key,
  reporter uuid references profiles (id) on delete set null,
  chat_id uuid references chats (id) on delete set null,
  message_id uuid references messages (id) on delete set null,
  target_user uuid references profiles (id) on delete set null,
  reason report_reason not null,
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

-- ---------- Уведомления, устройства, конфигурация ----------
create table notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles (id) on delete cascade,
  kind text not null,
  args jsonb not null default '{}',
  route text,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index notifications_user on notifications (user_id, created_at desc);

create table push_tokens (
  token text primary key,
  user_id uuid not null references profiles (id) on delete cascade,
  platform text not null check (platform in ('ios', 'android')),
  updated_at timestamptz not null default now()
);

create table app_config (
  key text primary key,
  value jsonb not null
);
insert into app_config values
  ('min_version', '"2.0.0"'), ('latest_version', '"2.0.0"'),
  ('flags', '{"chats": true, "rating": true, "feed": true}');

-- Номер портфолио для проверки: «TN» + 6 случайных символов без похожих 0/O/1/I; можно отозвать и выпустить новый.
create function gen_portfolio_code() returns text language sql volatile as $$
  select 'TN' || string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', 1 + (get_byte(b, i) % 32), 1), '')
  from (select gen_random_bytes(6) b) r, generate_series(0, 5) i
$$;

create table portfolio_tokens (
  user_id uuid primary key references profiles (id) on delete cascade,
  code text not null unique default gen_portfolio_code(),
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);
