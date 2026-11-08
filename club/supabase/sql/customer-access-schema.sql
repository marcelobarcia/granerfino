-- Applied customer access / assisted-members upgrade, preserved for fresh installs.
alter table public.gf_wallets add column if not exists customer_pin_hash text,
 add column if not exists customer_pin_salt text,
 add column if not exists legacy_access_enabled boolean not null default true,
 add column if not exists assisted boolean not null default false,
 add column if not exists registration_test_mode boolean not null default true,
 add column if not exists member_code text not null default ('GF-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10))) unique;
create index if not exists gf_member_phone_login on public.gf_wallets(phone) where customer_pin_hash is not null;
create table if not exists public.gf_customer_sessions (
 token_hash text primary key,wallet_hash text not null references public.gf_wallets(token_hash),
 created_at timestamptz not null default now(),expires_at timestamptz not null
);
create index if not exists gf_customer_session_wallet on public.gf_customer_sessions(wallet_hash);
create table if not exists public.gf_recovery_links (
 token_hash text primary key,wallet_hash text not null references public.gf_wallets(token_hash),
 created_at timestamptz not null default now(),expires_at timestamptz not null,used_at timestamptz,
 verified_at timestamptz not null default now()
);
create index if not exists gf_recovery_wallet on public.gf_recovery_links(wallet_hash);
alter table public.gf_customer_sessions enable row level security;
alter table public.gf_recovery_links enable row level security;
revoke all on public.gf_customer_sessions,public.gf_recovery_links from anon,authenticated;
grant all on public.gf_customer_sessions,public.gf_recovery_links to service_role;
