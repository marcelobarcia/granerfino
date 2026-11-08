-- Club Granero Fino v1. Tables are accessible only to the Edge Function.
create table public.gf_config (
 id boolean primary key default true check (id), test_mode boolean not null default true,
 min_purchase integer not null default 3000 check(min_purchase>=0), validity_days integer not null default 14 check(validity_days between 1 and 90),
 daily_budget integer not null default 10000 check(daily_budget>=0),
 password_hash text, password_salt text, setup_hash text,
 updated_at timestamptz not null default now()
);
create table public.gf_prizes (
 id integer primary key, title text not null, amount integer not null check(amount>0),
 min_purchase integer not null check(min_purchase>=amount), weight integer not null check(weight>=0), active boolean not null default true
);
create table public.gf_wallets (
 token_hash text primary key, name text not null, phone text not null,
 terms_version text not null default 'v1', marketing boolean not null default false, created_at timestamptz not null default now()
);
create table public.gf_tickets (
 token_hash text primary key, receipt text not null, purchase_amount integer not null check(purchase_amount>0),
 test_mode boolean not null, created_at timestamptz not null default now(), expires_at timestamptz not null,
 wallet_hash text, prize_id integer references public.gf_prizes(id), prize_title text, prize_amount integer, prize_min integer,
 spun_at timestamptz, prize_expires_at timestamptz, redeem_code text unique,
 redeemed_at timestamptz, redeem_receipt text, redeem_amount integer, revoked boolean not null default false,
 unique(receipt,test_mode)
);
create unique index gf_redeem_receipt on public.gf_tickets(redeem_receipt,test_mode) where redeemed_at is not null;
create index gf_wallet_tickets on public.gf_tickets(wallet_hash,created_at desc);
create index gf_spun_tickets on public.gf_tickets(spun_at) where spun_at is not null;
create table public.gf_sessions (token_hash text primary key, expires_at timestamptz not null);
create table public.gf_attempts (key text primary key, attempts integer not null default 1, reset_at timestamptz not null);
alter table public.gf_config enable row level security;
alter table public.gf_prizes enable row level security;
alter table public.gf_wallets enable row level security;
alter table public.gf_tickets enable row level security;
alter table public.gf_sessions enable row level security;
alter table public.gf_attempts enable row level security;
revoke all on public.gf_config,public.gf_prizes,public.gf_wallets,public.gf_tickets,public.gf_sessions,public.gf_attempts from anon,authenticated;
grant all on public.gf_config,public.gf_prizes,public.gf_wallets,public.gf_tickets,public.gf_sessions,public.gf_attempts to service_role;

create function public.gf_rate(p_key text,p_limit integer,p_seconds integer) returns boolean
language plpgsql security invoker set search_path='' as $$
declare n integer;
begin
 insert into public.gf_attempts(key,attempts,reset_at) values(p_key,1,now()+make_interval(secs=>p_seconds))
 on conflict(key) do update set attempts=case when gf_attempts.reset_at<now() then 1 else gf_attempts.attempts+1 end,
 reset_at=case when gf_attempts.reset_at<now() then now()+make_interval(secs=>p_seconds) else gf_attempts.reset_at end returning attempts into n;
 return n<=p_limit;
end $$;

create function public.gf_setup(p_setup text,p_hash text,p_salt text) returns boolean
language plpgsql security invoker set search_path='' as $$
begin
 update public.gf_config set password_hash=p_hash,password_salt=p_salt,setup_hash=null where id and setup_hash=p_setup and password_hash is null;
 return found;
end $$;

create function public.gf_spin(p_token text,p_wallet text,p_random double precision,p_code text) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare t public.gf_tickets; c public.gf_config; p public.gf_prizes; total integer; used integer; target double precision; acc integer:=0;
begin
 select * into t from public.gf_tickets where token_hash=p_token for update;
 if not found or t.revoked then raise exception 'Este giro no está disponible'; end if;
 if t.spun_at is not null then
  if t.wallet_hash is distinct from p_wallet then raise exception 'Este QR ya fue utilizado'; end if;
  return to_jsonb(t)-'token_hash'-'wallet_hash';
 end if;
 if t.expires_at<now() then raise exception 'El QR venció. Pedí uno nuevo en caja'; end if;
 select * into c from public.gf_config where id for update;
 select coalesce(sum(prize_amount),0) into used from public.gf_tickets
 where not test_mode and spun_at >= (date_trunc('day',now() at time zone 'America/Santiago') at time zone 'America/Santiago');
 select sum(weight) into total from public.gf_prizes where active and weight>0 and (t.test_mode or amount<=c.daily_budget-used);
 if total is null or total=0 then raise exception 'Los premios de hoy se agotaron. Tu giro sigue disponible'; end if;
 target=greatest(0,least(p_random,0.999999999))*total;
 for p in select * from public.gf_prizes where active and weight>0 and (t.test_mode or amount<=c.daily_budget-used) order by id loop
  acc=acc+p.weight; exit when target<acc;
 end loop;
 update public.gf_tickets set wallet_hash=p_wallet,prize_id=p.id,prize_title=p.title,prize_amount=p.amount,prize_min=p.min_purchase,
 spun_at=now(),prize_expires_at=now()+make_interval(days=>c.validity_days),redeem_code=p_code where token_hash=p_token returning * into t;
 return to_jsonb(t)-'token_hash'-'wallet_hash';
end $$;

create function public.gf_redeem(p_code text,p_receipt text,p_amount integer) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare t public.gf_tickets;
begin
 select * into t from public.gf_tickets where redeem_code=p_code for update;
 if not found or t.revoked then raise exception 'Premio no encontrado'; end if;
 if t.redeemed_at is not null then raise exception 'Este premio ya fue canjeado'; end if;
 if t.prize_expires_at<now() then raise exception 'Este premio venció'; end if;
 if not exists(select 1 from public.gf_wallets where token_hash=t.wallet_hash) then raise exception 'El cliente todavía no guardó su premio'; end if;
 if p_amount<t.prize_min then raise exception 'La compra no alcanza el mínimo del premio'; end if;
 if trim(p_receipt)='' or trim(p_receipt)=t.receipt then raise exception 'Usá el comprobante de una nueva compra'; end if;
 update public.gf_tickets set redeemed_at=now(),redeem_receipt=trim(p_receipt),redeem_amount=p_amount where token_hash=t.token_hash returning * into t;
 return to_jsonb(t)-'token_hash'-'wallet_hash';
end $$;
revoke all on function public.gf_rate(text,integer,integer),public.gf_setup(text,text,text),public.gf_spin(text,text,double precision,text),public.gf_redeem(text,text,integer) from public,anon,authenticated;
grant execute on function public.gf_rate(text,integer,integer),public.gf_setup(text,text,text),public.gf_spin(text,text,double precision,text),public.gf_redeem(text,text,integer) to service_role;
