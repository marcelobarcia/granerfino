create table public.gf_stamp_adjustments(
 id uuid primary key default gen_random_uuid(),card_id uuid not null references public.gf_cards(id),
 before_count integer not null,after_count integer not null,reason text not null check(length(trim(reason)) between 3 and 200),
 staff_session_hash text not null,created_at timestamptz not null default now()
);
alter table public.gf_stamp_adjustments enable row level security;
revoke all on public.gf_stamp_adjustments from anon,authenticated;
grant all on public.gf_stamp_adjustments to service_role;
create function public.gf_adjust_stamps(p_member uuid,p_mode boolean,p_card uuid,p_expected integer,p_target integer,p_reason text,p_staff text) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare w public.gf_wallets;c public.gf_cards;cfg public.gf_config;old_count integer;bonus public.gf_bonus_rewards;note text:='';
begin
 select * into w from public.gf_wallets where member_id=p_member for update;
 if not found then raise exception 'Cliente no encontrado';end if;
 select * into cfg from public.gf_config where id for update;
 if p_card is null then
  if exists(select 1 from public.gf_cards where wallet_hash=w.token_hash and test_mode=p_mode) then raise exception 'La tarjeta cambió. Abrí la ficha nuevamente';end if;
  insert into public.gf_cards(wallet_hash,test_mode,goal,min_purchase,repeat_card,reward_kind,reward_title,reward_amount,reward_min,reward_days)
  values(w.token_hash,p_mode,cfg.stamp_goal,cfg.stamp_min_purchase,cfg.stamp_repeat,cfg.stamp_reward_kind,cfg.stamp_reward_title,cfg.stamp_reward_amount,cfg.stamp_reward_min,cfg.stamp_reward_days) returning * into c;
 else
  select * into c from public.gf_cards where id=p_card and wallet_hash=w.token_hash and test_mode=p_mode for update;
  if not found then raise exception 'Tarjeta no encontrada';end if;
 end if;
 if c.progress<>p_expected then raise exception 'Los sellos cambiaron. Abrí la ficha nuevamente';end if;
 if p_target is null or p_target<0 or p_target>c.goal or length(trim(p_reason)) not between 3 and 200 then raise exception 'Revisá cantidad y motivo';end if;
 if p_target=c.progress then raise exception 'La cantidad es la misma';end if;
 old_count=c.progress;
 if p_target<c.goal and c.completed_at is not null and exists(select 1 from public.gf_cards where wallet_hash=w.token_hash and test_mode=p_mode and id<>c.id and completed_at is null) then
  raise exception 'Ya hay otra tarjeta abierta. Ajustá los sellos de la tarjeta actual';end if;
 update public.gf_cards set progress=p_target,completed_at=case when p_target=goal then coalesce(completed_at,now()) else null end where id=c.id;
 select * into bonus from public.gf_bonus_rewards where card_id=c.id for update;
 if p_target<c.goal and bonus.id is not null then
  update public.gf_bonus_rewards set revoked=true where id=bonus.id;
  if bonus.redeemed_at is not null then note:='El premio ya fue entregado: este ajuste no revierte la entrega en Odoo';end if;
 end if;
 if p_target=c.goal then
  if bonus.id is null then
   insert into public.gf_bonus_rewards(card_id,wallet_hash,test_mode,prize_kind,prize_title,prize_amount,prize_min,prize_expires_at,redeem_code,origin_receipt,redeemed_at,redeem_receipt,redeem_amount)
   values(c.id,w.token_hash,p_mode,c.reward_kind,c.reward_title,c.reward_amount,c.reward_min,now()+make_interval(days=>c.reward_days),'GC-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12)),'AJUSTE-'||c.id,now(),'AJUSTE-'||c.id,0);
   note:='Tarjeta completa: entregar ahora '||c.reward_title;
  elsif bonus.redeemed_at is not null then note:='El premio de esta tarjeta ya fue entregado. No se genera otro';
  else
   update public.gf_bonus_rewards set revoked=false,redeemed_at=now(),redeem_receipt='AJUSTE-'||c.id,redeem_amount=0 where id=bonus.id;
   note:='Tarjeta completa: entregar ahora '||c.reward_title;
  end if;
 end if;
 insert into public.gf_stamp_adjustments(card_id,before_count,after_count,reason,staff_session_hash) values(c.id,old_count,p_target,trim(p_reason),p_staff);
 return jsonb_build_object('ok',true,'note',note,'before',old_count,'after',p_target);
end $$;
revoke all on function public.gf_adjust_stamps(uuid,boolean,uuid,integer,integer,text,text) from public,anon,authenticated;
grant execute on function public.gf_adjust_stamps(uuid,boolean,uuid,integer,integer,text,text) to service_role;

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
    now()+make_interval(days=>card.reward_days),'GC-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12)),t.receipt) on conflict(card_id) do nothing;
 end if;
end $$;


do $$ declare s text; begin select pg_get_functiondef('public.gf_members(text,boolean,boolean,integer,integer)'::regprocedure) into s; s=replace(s,'(select count(*) from public.gf_stamps s join public.gf_cards c on c.id=s.card_id where c.wallet_hash=p.token_hash and c.test_mode=p_mode) as stamps','(select coalesce(sum(c.progress),0) from public.gf_cards c where c.wallet_hash=p.token_hash and c.test_mode=p_mode) as stamps');execute s;end $$;
