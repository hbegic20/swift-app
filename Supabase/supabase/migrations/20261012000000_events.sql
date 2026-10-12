-- One table for every event type (rule 1): messages, notifications and any
-- type a future server adds. The app routes on `type`.
create table public.events (
  -- One shared counter for all types, handed out by Postgres (rule 10).
  -- Catch-up asks for everything after the highest one the app has.
  sequence   bigint generated always as identity primary key,
  -- The app dedupes on this (rule 3).
  id         text not null unique default gen_random_uuid()::text,
  user_id    uuid not null references auth.users (id) on delete cascade,
  type       text not null,
  -- The type-specific fields, e.g. {"chatID", "senderID", "text"}.
  payload    jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index events_user_sequence on public.events (user_id, sequence);

-- Each user reads only their own events. The app never writes; rows are
-- added by the server (here: Supabase/send.sh as the database owner).
alter table public.events enable row level security;

create policy "users read their own events"
  on public.events for select
  to authenticated
  using (user_id = (select auth.uid()));

grant select on public.events to authenticated;

-- Send inserts on this table over Realtime (Postgres Changes).
-- Realtime applies the policy above per subscriber.
alter publication supabase_realtime add table public.events;
