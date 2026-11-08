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
 if total is null or total=0 or not exists(select 1 from jsonb_array_elements(pool) x where x->>'kind'='discount') then raise exception 'No hay premios habilitados para esta compra hoy. Consultá en Caja; tu giro sigue disponible'; end if;
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


create or replace function public.gf_settings(p_config jsonb,p_prizes jsonb) returns void
language plpgsql security invoker set search_path='' as $$
declare p jsonb;
begin
 perform 1 from public.gf_config where id for update;
 if jsonb_array_length(p_prizes) not in (3,4) or (select count(distinct (value->>'id')::integer) from jsonb_array_elements(p_prizes))<>jsonb_array_length(p_prizes) then raise exception 'Revisá los premios'; end if;
 if not exists(select 1 from jsonb_array_elements(p_prizes) x where (x->>'id')::integer<>4 and (x->>'weight')::integer>0 and (x->>'amount')::integer<=(p_config->>'daily_budget')::integer and (x->>'min_purchase')::integer<=(p_config->>'min_purchase')::integer) then raise exception 'Debe existir un premio habilitado desde el mínimo para girar y dentro del presupuesto'; end if;
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


create function public.gf_pending_prizes(p_mode boolean,p_search text,p_page integer,p_size integer) returns jsonb
language sql security invoker set search_path='' as $$
 with prizes as (
  select t.redeem_code,t.prize_title,t.prize_amount,t.prize_min,t.prize_expires_at,t.created_at,t.test_mode,t.allow_same_purchase,
   t.receipt,t.purchase_amount,'discount'::text as prize_kind,'roulette'::text as reward_source,w.name,w.member_code
  from public.gf_tickets t left join public.gf_wallets w on w.token_hash=t.wallet_hash
  where t.test_mode=p_mode and t.outcome='prize' and not t.revoked and t.redeemed_at is null and t.prize_expires_at>now()
  union all
  select b.redeem_code,b.prize_title,b.prize_amount,b.prize_min,b.prize_expires_at,b.created_at,b.test_mode,b.allow_same_purchase,
   b.origin_receipt,t.purchase_amount,b.prize_kind,'loyalty'::text,w.name,w.member_code
  from public.gf_bonus_rewards b left join public.gf_wallets w on w.token_hash=b.wallet_hash
   left join public.gf_tickets t on t.receipt=b.origin_receipt and t.test_mode=b.test_mode
  where b.test_mode=p_mode and not b.revoked and b.redeemed_at is null and b.prize_expires_at>now()
 ), matched as (
  select p.*,p.allow_same_purchase and coalesce(p.purchase_amount,0)>=p.prize_min as quick_redeem from prizes p
  where p_search='' or strpos(lower(coalesce(p.name,'')),lower(p_search))>0 or strpos(lower(p.receipt),lower(p_search))>0
   or strpos(lower(p.redeem_code),lower(p_search))>0 or strpos(lower(coalesce(p.member_code,'')),lower(p_search))>0
 ), paged as (
  select * from matched order by created_at desc,redeem_code limit least(greatest(p_size,1),100) offset greatest(p_page,0)*least(greatest(p_size,1),100)
 ) select jsonb_build_object('total',(select count(*) from matched),'items',coalesce((select jsonb_agg(to_jsonb(p) order by p.created_at desc,p.redeem_code) from paged p),'[]'::jsonb));
$$;
revoke all on function public.gf_pending_prizes(boolean,text,integer,integer) from public,anon,authenticated;
grant execute on function public.gf_pending_prizes(boolean,text,integer,integer) to service_role;
