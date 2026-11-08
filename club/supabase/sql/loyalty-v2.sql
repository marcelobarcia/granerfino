-- Append-only upgrade. Existing coupons and customer access are preserved.
alter table public.gf_config
 add column stamp_enabled boolean not null default true,
 add column stamp_goal integer not null default 5 check(stamp_goal between 2 and 20),
 add column stamp_min_purchase integer not null default 3000 check(stamp_min_purchase between 1 and 10000000),
 add column stamp_repeat boolean not null default true,
 add column stamp_reward_kind text not null default 'discount' check(stamp_reward_kind in ('discount','product')),
 add column stamp_reward_title text not null default 'Premio especial por completar tu tarjeta' check(length(stamp_reward_title) between 1 and 100),
 add column stamp_reward_amount integer not null default 1500 check(stamp_reward_amount between 0 and 10000000),
 add column stamp_reward_min integer not null default 15000 check(stamp_reward_min between 1 and 10000000),
 add column stamp_reward_days integer not null default 30 check(stamp_reward_days between 1 and 365),
 add constraint gf_stamp_discount_valid check(stamp_reward_kind<>'discount' or (stamp_reward_amount>0 and stamp_reward_min>=stamp_reward_amount));
alter table public.gf_wallets add column member_id uuid not null default gen_random_uuid() unique;

create table public.gf_cards (
 id uuid primary key default gen_random_uuid(), wallet_hash text not null, test_mode boolean not null,
 progress integer not null default 0 check(progress>=0), goal integer not null check(goal between 2 and 20),
 min_purchase integer not null, repeat_card boolean not null,
 reward_kind text not null, reward_title text not null, reward_amount integer not null,
 reward_min integer not null, reward_days integer not null,
 created_at timestamptz not null default now(), completed_at timestamptz,
 check(progress<=goal)
);
create unique index gf_one_open_card on public.gf_cards(wallet_hash,test_mode) where completed_at is null;
create index gf_card_wallet on public.gf_cards(wallet_hash,test_mode,created_at desc);
create table public.gf_stamps (
 ticket_hash text primary key references public.gf_tickets(token_hash),
 card_id uuid not null references public.gf_cards(id), created_at timestamptz not null default now()
);
create index gf_stamp_card on public.gf_stamps(card_id);
create table public.gf_bonus_rewards (
 id uuid primary key default gen_random_uuid(), card_id uuid not null unique references public.gf_cards(id),
 wallet_hash text not null, test_mode boolean not null, prize_kind text not null,
 prize_title text not null, prize_amount integer not null, prize_min integer not null,
 prize_expires_at timestamptz not null, redeem_code text not null unique, origin_receipt text not null,
 created_at timestamptz not null default now(), redeemed_at timestamptz, redeem_receipt text, redeem_amount integer,
 revoked boolean not null default false
);
create index gf_bonus_wallet on public.gf_bonus_rewards(wallet_hash,created_at desc);
create table public.gf_redemptions (
 receipt text not null, test_mode boolean not null, redeem_code text not null unique,
 created_at timestamptz not null default now(), primary key(receipt,test_mode)
);
insert into public.gf_redemptions(receipt,test_mode,redeem_code,created_at)
 select redeem_receipt,test_mode,redeem_code,redeemed_at from public.gf_tickets where redeemed_at is not null
 on conflict do nothing;
alter table public.gf_cards enable row level security;
alter table public.gf_stamps enable row level security;
alter table public.gf_bonus_rewards enable row level security;
alter table public.gf_redemptions enable row level security;
revoke all on public.gf_cards,public.gf_stamps,public.gf_bonus_rewards,public.gf_redemptions from anon,authenticated;
grant all on public.gf_cards,public.gf_stamps,public.gf_bonus_rewards,public.gf_redemptions to service_role;

create function public.gf_stamp_info(p_token text) returns jsonb
language sql security invoker set search_path='' as $$
 select jsonb_build_object('stamp_earned',s.ticket_hash is not null,
  'stamp_card',case when c.id is null then null else to_jsonb(c)-'wallet_hash' end,
  'stamp_bonus',case when b.id is null then null else to_jsonb(b)-'wallet_hash' end)
 from (values(1)) as dummy(n)
 left join public.gf_stamps s on s.ticket_hash=p_token
 left join public.gf_cards c on c.id=s.card_id
 left join public.gf_bonus_rewards b on b.card_id=c.id;
$$;

create function public.gf_award_stamp(p_token text) returns void
language plpgsql security invoker set search_path='' as $$
declare t public.gf_tickets; cfg public.gf_config; card public.gf_cards; last_card public.gf_cards;
begin
 select * into t from public.gf_tickets where token_hash=p_token;
 if t.spun_at is null or t.wallet_hash is null or t.revoked or exists(select 1 from public.gf_stamps where ticket_hash=p_token) then return; end if;
 select * into cfg from public.gf_config where id for update;
 if not cfg.stamp_enabled then return; end if;
 select * into card from public.gf_cards where wallet_hash=t.wallet_hash and test_mode=t.test_mode and completed_at is null for update;
 if card.id is null then
  select * into last_card from public.gf_cards where wallet_hash=t.wallet_hash and test_mode=t.test_mode order by created_at desc limit 1;
  if last_card.id is not null and not last_card.repeat_card then return; end if;
  if t.purchase_amount<cfg.stamp_min_purchase then return; end if;
  insert into public.gf_cards(wallet_hash,test_mode,goal,min_purchase,repeat_card,reward_kind,reward_title,reward_amount,reward_min,reward_days)
   values(t.wallet_hash,t.test_mode,cfg.stamp_goal,cfg.stamp_min_purchase,cfg.stamp_repeat,cfg.stamp_reward_kind,cfg.stamp_reward_title,cfg.stamp_reward_amount,cfg.stamp_reward_min,cfg.stamp_reward_days) returning * into card;
 end if;
 if t.purchase_amount<card.min_purchase then return; end if;
 insert into public.gf_stamps(ticket_hash,card_id) values(p_token,card.id);
 update public.gf_cards set progress=progress+1,completed_at=case when progress+1=goal then now() else null end where id=card.id returning * into card;
 if card.progress=card.goal then
  insert into public.gf_bonus_rewards(card_id,wallet_hash,test_mode,prize_kind,prize_title,prize_amount,prize_min,prize_expires_at,redeem_code,origin_receipt)
   values(card.id,t.wallet_hash,t.test_mode,card.reward_kind,card.reward_title,card.reward_amount,card.reward_min,
    now()+make_interval(days=>card.reward_days),'GC-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12)),t.receipt);
 end if;
end $$;

create or replace function public.gf_spin(p_token text,p_wallet text,p_random double precision,p_code text) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare t public.gf_tickets; c public.gf_config; p public.gf_prizes; total integer; used integer; target double precision; acc integer:=0;
begin
 select * into t from public.gf_tickets where token_hash=p_token for update;
 if not found or t.revoked then raise exception 'Este giro no está disponible'; end if;
 if t.spun_at is not null then
  if t.wallet_hash is distinct from p_wallet then raise exception 'Este QR ya fue utilizado'; end if;
  return (to_jsonb(t)-'token_hash'-'wallet_hash')||public.gf_stamp_info(p_token);
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
 perform public.gf_award_stamp(p_token);
 return (to_jsonb(t)-'token_hash'-'wallet_hash')||public.gf_stamp_info(p_token);
end $$;

create or replace function public.gf_redeem(p_code text,p_receipt text,p_amount integer) returns jsonb
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
 insert into public.gf_redemptions(receipt,test_mode,redeem_code) values(trim(p_receipt),t.test_mode,p_code);
 update public.gf_tickets set redeemed_at=now(),redeem_receipt=trim(p_receipt),redeem_amount=p_amount where token_hash=t.token_hash returning * into t;
 return to_jsonb(t)-'token_hash'-'wallet_hash';
end $$;

create function public.gf_bonus_redeem(p_code text,p_receipt text,p_amount integer) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare b public.gf_bonus_rewards;
begin
 select * into b from public.gf_bonus_rewards where redeem_code=p_code for update;
 if not found or b.revoked then raise exception 'Premio especial no encontrado'; end if;
 if b.redeemed_at is not null then raise exception 'Este premio ya fue canjeado'; end if;
 if b.prize_expires_at<now() then raise exception 'Este premio venció'; end if;
 if not exists(select 1 from public.gf_wallets where token_hash=b.wallet_hash) then raise exception 'El cliente todavía no guardó su premio'; end if;
 if p_amount<b.prize_min then raise exception 'La compra no alcanza el mínimo del premio'; end if;
 if trim(p_receipt)='' or trim(p_receipt)=b.origin_receipt then raise exception 'Usá el comprobante de una nueva compra'; end if;
 insert into public.gf_redemptions(receipt,test_mode,redeem_code) values(trim(p_receipt),b.test_mode,p_code);
 update public.gf_bonus_rewards set redeemed_at=now(),redeem_receipt=trim(p_receipt),redeem_amount=p_amount where id=b.id returning * into b;
 return to_jsonb(b)-'wallet_hash';
end $$;

create function public.gf_settings(p_config jsonb,p_prizes jsonb) returns void
language plpgsql security invoker set search_path='' as $$
declare p jsonb;
begin
 perform 1 from public.gf_config where id for update;
 if jsonb_array_length(p_prizes)<>3 or (select count(distinct (value->>'id')::integer) from jsonb_array_elements(p_prizes))<>3 then raise exception 'Revisá los premios'; end if;
 if not exists(select 1 from jsonb_array_elements(p_prizes) x where (x->>'weight')::integer>0 and (x->>'amount')::integer<=(p_config->>'daily_budget')::integer) then raise exception 'El presupuesto debe alcanzar para un premio'; end if;
 update public.gf_config set test_mode=(p_config->>'test_mode')::boolean,min_purchase=(p_config->>'min_purchase')::integer,
  validity_days=(p_config->>'validity_days')::integer,daily_budget=(p_config->>'daily_budget')::integer,
  stamp_enabled=(p_config->>'stamp_enabled')::boolean,stamp_goal=(p_config->>'stamp_goal')::integer,
  stamp_min_purchase=(p_config->>'stamp_min_purchase')::integer,stamp_repeat=(p_config->>'stamp_repeat')::boolean,
  stamp_reward_kind=p_config->>'stamp_reward_kind',stamp_reward_title=p_config->>'stamp_reward_title',
  stamp_reward_amount=(p_config->>'stamp_reward_amount')::integer,stamp_reward_min=(p_config->>'stamp_reward_min')::integer,
  stamp_reward_days=(p_config->>'stamp_reward_days')::integer,updated_at=now() where id;
 for p in select * from jsonb_array_elements(p_prizes) loop
  if (p->>'id')::integer not in (1,2,3) then raise exception 'Premio no válido'; end if;
  update public.gf_prizes set amount=(p->>'amount')::integer,min_purchase=(p->>'min_purchase')::integer,
   weight=(p->>'weight')::integer,title=p->>'title',active=true where id=(p->>'id')::integer;
 end loop;
end $$;

revoke all on function public.gf_stamp_info(text),public.gf_award_stamp(text),public.gf_bonus_redeem(text,text,integer),public.gf_settings(jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.gf_stamp_info(text),public.gf_award_stamp(text),public.gf_bonus_redeem(text,text,integer),public.gf_settings(jsonb,jsonb) to service_role;

create function public.gf_members(p_search text,p_mode boolean,p_marketing boolean,p_page integer,p_size integer) returns jsonb
language sql security invoker set search_path='' as $$
 with matched as (
  select w.* from public.gf_wallets w
  where (p_search='' or strpos(lower(w.name),lower(p_search))>0 or strpos(w.phone,p_search)>0)
   and (not p_marketing or w.marketing)
   and exists(select 1 from public.gf_tickets t where t.wallet_hash=w.token_hash and t.test_mode=p_mode)
 ), paged as (
  select * from matched order by created_at desc,member_id limit least(greatest(p_size,1),500) offset greatest(p_page,0)*least(greatest(p_size,1),500)
 ), items as (
  select p.member_id,p.name,p.phone,p.marketing,p.created_at,
   (select count(*) from public.gf_tickets t where t.wallet_hash=p.token_hash and t.test_mode=p_mode and t.spun_at is not null) as purchases,
   (select count(*) from public.gf_stamps s join public.gf_cards c on c.id=s.card_id where c.wallet_hash=p.token_hash and c.test_mode=p_mode) as stamps,
   ((select count(*) from public.gf_tickets t where t.wallet_hash=p.token_hash and t.test_mode=p_mode and t.spun_at is not null and not t.revoked and t.redeemed_at is null and t.prize_expires_at>now())+
    (select count(*) from public.gf_bonus_rewards b where b.wallet_hash=p.token_hash and b.test_mode=p_mode and not b.revoked and b.redeemed_at is null and b.prize_expires_at>now())) as available_prizes
  from paged p
 ) select jsonb_build_object('total',(select count(*) from matched),'items',coalesce((select jsonb_agg(to_jsonb(i) order by i.created_at desc,i.member_id) from items i),'[]'::jsonb));
$$;
revoke all on function public.gf_members(text,boolean,boolean,integer,integer) from public,anon,authenticated;
grant execute on function public.gf_members(text,boolean,boolean,integer,integer) to service_role;
