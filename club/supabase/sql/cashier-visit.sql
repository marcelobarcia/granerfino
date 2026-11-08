alter table public.gf_tickets add column cashier_verified boolean not null default false;
alter table public.gf_tickets drop constraint gf_tickets_purchase_amount_check;
alter table public.gf_tickets add constraint gf_tickets_purchase_amount_check check(purchase_amount>0 or (cashier_verified and purchase_amount=0));
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
   and (kind='none' or ((t.cashier_verified or min_purchase<=t.purchase_amount) and (t.test_mode or amount<=c.daily_budget-used)))) x;
 if total is null or total=0 or not exists(select 1 from jsonb_array_elements(pool) x where x->>'kind'='discount') then raise exception 'No hay premios habilitados para esta compra hoy. Consultá en Caja; tu giro sigue disponible'; end if;
 target=greatest(0,least(p_random,0.999999999))*total;
 for p in select * from public.gf_prizes where active and weight>0
  and (kind='none' or ((t.cashier_verified or min_purchase<=t.purchase_amount) and (t.test_mode or amount<=c.daily_budget-used))) order by id loop
  acc=acc+p.weight; exit when target<acc;
 end loop;
 update public.gf_tickets set wallet_hash=p_wallet,prize_id=p.id,prize_title=p.title,prize_amount=p.amount,prize_min=p.min_purchase,
  outcome=case when p.kind='none' then 'none' else 'prize' end,allow_same_purchase=true,wheel_prizes=pool,spun_at=now(),
  prize_expires_at=case when p.kind='none' then null else now()+make_interval(days=>c.validity_days) end,
  redeem_code=case when p.kind='none' then null else p_code end where token_hash=p_token returning * into t;
 perform public.gf_award_stamp(p_token);
 return (to_jsonb(t)-'token_hash'-'wallet_hash')||public.gf_stamp_info(p_token);
end $$;


create or replace function public.gf_award_stamp(p_token text) returns void
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
  if not t.cashier_verified and t.purchase_amount<cfg.stamp_min_purchase then return; end if;
  insert into public.gf_cards(wallet_hash,test_mode,goal,min_purchase,repeat_card,reward_kind,reward_title,reward_amount,reward_min,reward_days)
   values(t.wallet_hash,t.test_mode,cfg.stamp_goal,cfg.stamp_min_purchase,cfg.stamp_repeat,cfg.stamp_reward_kind,cfg.stamp_reward_title,cfg.stamp_reward_amount,cfg.stamp_reward_min,cfg.stamp_reward_days) returning * into card;
 end if;
 if not t.cashier_verified and t.purchase_amount<card.min_purchase then return; end if;
 insert into public.gf_stamps(ticket_hash,card_id) values(p_token,card.id);
 update public.gf_cards set progress=progress+1,completed_at=case when progress+1=goal then now() else null end where id=card.id returning * into card;
 if card.progress=card.goal then
  insert into public.gf_bonus_rewards(card_id,wallet_hash,test_mode,prize_kind,prize_title,prize_amount,prize_min,prize_expires_at,redeem_code,origin_receipt)
   values(card.id,t.wallet_hash,t.test_mode,card.reward_kind,card.reward_title,card.reward_amount,card.reward_min,
    now()+make_interval(days=>card.reward_days),'GC-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12)),t.receipt);
 end if;
end $$;


create function public.gf_cashier_visit(p_wallet text,p_token text,p_random double precision,p_code text) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare c public.gf_config; t public.gf_tickets; r jsonb;
begin
 perform 1 from public.gf_wallets where token_hash=p_wallet for update;
 if not found then raise exception 'Miembro no encontrado';end if;
 select * into t from public.gf_tickets where token_hash=p_token;
 if found then
  if t.wallet_hash<>p_wallet or not t.cashier_verified then raise exception 'Operación no válida';end if;
  return (to_jsonb(t)-'token_hash'-'wallet_hash')||public.gf_stamp_info(p_token);
 end if;
 select * into c from public.gf_config where id for update;
 insert into public.gf_tickets(token_hash,receipt,purchase_amount,test_mode,expires_at,cashier_verified)
 values(p_token,'CAJA-'||upper(substr(p_token,1,20)),0,c.test_mode,now()+interval '1 day',true);
 r=public.gf_spin(p_token,p_wallet,p_random,p_code);
 update public.gf_tickets set redeemed_at=now(),redeem_receipt=receipt,redeem_amount=0 where token_hash=p_token and outcome='prize';
 insert into public.gf_redemptions(receipt,test_mode,redeem_code) select receipt,test_mode,redeem_code from public.gf_tickets where token_hash=p_token and outcome='prize';
 update public.gf_bonus_rewards set redeemed_at=now(),redeem_receipt=origin_receipt,redeem_amount=0 where origin_receipt=r->>'receipt' and wallet_hash=p_wallet and test_mode=c.test_mode and redeemed_at is null;
 select * into t from public.gf_tickets where token_hash=p_token;
 return (to_jsonb(t)-'token_hash'-'wallet_hash')||public.gf_stamp_info(p_token);
end $$;
revoke all on function public.gf_cashier_visit(text,text,double precision,text) from public,anon,authenticated;
grant execute on function public.gf_cashier_visit(text,text,double precision,text) to service_role;
