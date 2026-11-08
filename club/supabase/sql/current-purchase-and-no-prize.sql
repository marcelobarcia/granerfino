alter table public.gf_prizes add column kind text not null default 'discount' check(kind in('discount','none'));
alter table public.gf_prizes drop constraint gf_prizes_amount_check;
alter table public.gf_prizes add constraint gf_prizes_amount_check check((kind='none' and amount=0) or (kind='discount' and amount>0));
insert into public.gf_prizes(id,title,amount,min_purchase,weight,kind) values(4,'Sigue participando',0,0,25,'none');
alter table public.gf_tickets add column outcome text not null default 'prize' check(outcome in('prize','none')),
 add column allow_same_purchase boolean not null default false,add column wheel_prizes jsonb;
alter table public.gf_bonus_rewards add column allow_same_purchase boolean not null default false;
alter table public.gf_bonus_rewards alter column allow_same_purchase set default true;

create or replace function public.gf_spin(p_token text,p_wallet text,p_random double precision,p_code text) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare t public.gf_tickets; c public.gf_config; p public.gf_prizes; total integer; used integer; target double precision; acc integer:=0; pool jsonb;
begin
 select * into t from public.gf_tickets where token_hash=p_token for update;
 if not found or t.revoked then raise exception 'Este giro no está disponible'; end if;
 if t.spun_at is not null then
  if t.wallet_hash is distinct from p_wallet then raise exception 'Este QR ya fue utilizado'; end if;
  return (to_jsonb(t)-'token_hash'-'wallet_hash')||public.gf_stamp_info(p_token);
 end if;
 if t.expires_at<now() then raise exception 'El QR venció. Pedí uno nuevo en caja'; end if;
 select * into c from public.gf_config where id for update;
 select coalesce(sum(prize_amount),0) into used from public.gf_tickets where not test_mode
  and spun_at >= (date_trunc('day',now() at time zone 'America/Santiago') at time zone 'America/Santiago');
 select sum(weight),jsonb_agg(to_jsonb(x) order by id) into total,pool from
  (select id,title,amount,min_purchase,weight,kind from public.gf_prizes where active and weight>0
   and (kind='none' or (min_purchase<=t.purchase_amount and (t.test_mode or amount<=c.daily_budget-used)))) x;
 if total is null or total=0 then raise exception 'No hay resultados disponibles para esta compra. Tu giro sigue disponible'; end if;
 target=greatest(0,least(p_random,0.999999999))*total;
 for p in select * from public.gf_prizes where active and weight>0
  and (kind='none' or (min_purchase<=t.purchase_amount and (t.test_mode or amount<=c.daily_budget-used))) order by id loop
  acc=acc+p.weight; exit when target<acc;
 end loop;
 update public.gf_tickets set wallet_hash=p_wallet,prize_id=p.id,prize_title=p.title,prize_amount=p.amount,prize_min=p.min_purchase,
  outcome=case when p.kind='none' then 'none' else 'prize' end,allow_same_purchase=true,wheel_prizes=pool,spun_at=now(),
  prize_expires_at=case when p.kind='none' then null else now()+make_interval(days=>c.validity_days) end,
  redeem_code=case when p.kind='none' then null else p_code end where token_hash=p_token returning * into t;
 perform public.gf_award_stamp(p_token);
 return (to_jsonb(t)-'token_hash'-'wallet_hash')||public.gf_stamp_info(p_token);
end $$;

create or replace function public.gf_redeem(p_code text,p_receipt text,p_amount integer) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare t public.gf_tickets;
begin
 select * into t from public.gf_tickets where redeem_code=p_code for update;
 if not found or t.revoked or t.outcome='none' then raise exception 'Premio no encontrado'; end if;
 if t.redeemed_at is not null then raise exception 'Este premio ya fue canjeado'; end if;
 if t.prize_expires_at<now() then raise exception 'Este premio venció'; end if;
 if not t.allow_same_purchase and not exists(select 1 from public.gf_wallets where token_hash=t.wallet_hash) then raise exception 'El cliente todavía no guardó su premio'; end if;
 if p_amount<t.prize_min then raise exception 'La compra no alcanza el mínimo del premio'; end if;
 if trim(p_receipt)='' then raise exception 'Ingresá el comprobante o folio de la compra'; end if;
 if not t.allow_same_purchase and trim(p_receipt)=t.receipt then raise exception 'Este cupón anterior requiere una nueva compra'; end if;
 if t.allow_same_purchase and trim(p_receipt)=t.receipt and p_amount<>t.purchase_amount then raise exception 'El monto debe coincidir con el registrado al generar el giro'; end if;
 insert into public.gf_redemptions(receipt,test_mode,redeem_code) values(trim(p_receipt),t.test_mode,p_code);
 update public.gf_tickets set redeemed_at=now(),redeem_receipt=trim(p_receipt),redeem_amount=p_amount where token_hash=t.token_hash returning * into t;
 return to_jsonb(t)-'token_hash'-'wallet_hash';
end $$;

create or replace function public.gf_settings(p_config jsonb,p_prizes jsonb) returns void
language plpgsql security invoker set search_path='' as $$
declare p jsonb;
begin
 perform 1 from public.gf_config where id for update;
 if jsonb_array_length(p_prizes) not in (3,4) or (select count(distinct (value->>'id')::integer) from jsonb_array_elements(p_prizes))<>jsonb_array_length(p_prizes) then raise exception 'Revisá los premios'; end if;
 if not exists(select 1 from jsonb_array_elements(p_prizes) x where (x->>'weight')::integer>0 and (x->>'amount')::integer<=(p_config->>'daily_budget')::integer) then raise exception 'El presupuesto debe alcanzar para un premio'; end if;
 update public.gf_config set test_mode=(p_config->>'test_mode')::boolean,min_purchase=(p_config->>'min_purchase')::integer,
  validity_days=(p_config->>'validity_days')::integer,daily_budget=(p_config->>'daily_budget')::integer,
  stamp_enabled=(p_config->>'stamp_enabled')::boolean,stamp_goal=(p_config->>'stamp_goal')::integer,
  stamp_min_purchase=(p_config->>'stamp_min_purchase')::integer,stamp_repeat=(p_config->>'stamp_repeat')::boolean,
  stamp_reward_kind=p_config->>'stamp_reward_kind',stamp_reward_title=p_config->>'stamp_reward_title',
  stamp_reward_amount=(p_config->>'stamp_reward_amount')::integer,stamp_reward_min=(p_config->>'stamp_reward_min')::integer,
  stamp_reward_days=(p_config->>'stamp_reward_days')::integer,updated_at=now() where id;
 for p in select * from jsonb_array_elements(p_prizes) loop
  if (p->>'id')::integer not in (1,2,3,4) then raise exception 'Premio no válido'; end if;
  update public.gf_prizes set amount=(p->>'amount')::integer,min_purchase=(p->>'min_purchase')::integer,
   weight=(p->>'weight')::integer,title=p->>'title',active=true where id=(p->>'id')::integer;
 end loop;
end $$;


create or replace function public.gf_bonus_redeem(p_code text,p_receipt text,p_amount integer) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare b public.gf_bonus_rewards;
begin
 select * into b from public.gf_bonus_rewards where redeem_code=p_code for update;
 if not found or b.revoked then raise exception 'Premio especial no encontrado'; end if;
 if b.redeemed_at is not null then raise exception 'Este premio ya fue canjeado'; end if;
 if b.prize_expires_at<now() then raise exception 'Este premio venció'; end if;
 if not exists(select 1 from public.gf_wallets where token_hash=b.wallet_hash) then raise exception 'El cliente todavía no guardó su premio'; end if;
 if p_amount<b.prize_min then raise exception 'La compra no alcanza el mínimo del premio'; end if;
 if trim(p_receipt)='' or (not b.allow_same_purchase and trim(p_receipt)=b.origin_receipt) then raise exception 'Usá el comprobante de una nueva compra'; end if;
 insert into public.gf_redemptions(receipt,test_mode,redeem_code) values(trim(p_receipt),b.test_mode,p_code);
 update public.gf_bonus_rewards set redeemed_at=now(),redeem_receipt=trim(p_receipt),redeem_amount=p_amount where id=b.id returning * into b;
 return to_jsonb(b)-'wallet_hash';
end $$;

