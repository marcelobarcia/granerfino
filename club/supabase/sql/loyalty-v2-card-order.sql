-- Deterministic card sequence even when several cycles share a timestamp.
alter table public.gf_cards add column cycle integer not null default 1 check(cycle>0);
with ordered as (select id,row_number() over(partition by wallet_hash,test_mode order by created_at,(completed_at is null),id) as n from public.gf_cards)
update public.gf_cards c set cycle=o.n from ordered o where c.id=o.id;
create unique index gf_card_cycle on public.gf_cards(wallet_hash,test_mode,cycle);
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
  select * into last_card from public.gf_cards where wallet_hash=t.wallet_hash and test_mode=t.test_mode order by cycle desc limit 1;
  if last_card.id is not null and not last_card.repeat_card then return; end if;
  if t.purchase_amount<cfg.stamp_min_purchase then return; end if;
  insert into public.gf_cards(wallet_hash,test_mode,cycle,goal,min_purchase,repeat_card,reward_kind,reward_title,reward_amount,reward_min,reward_days)
   values(t.wallet_hash,t.test_mode,coalesce(last_card.cycle,0)+1,cfg.stamp_goal,cfg.stamp_min_purchase,cfg.stamp_repeat,cfg.stamp_reward_kind,cfg.stamp_reward_title,cfg.stamp_reward_amount,cfg.stamp_reward_min,cfg.stamp_reward_days) returning * into card;
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

