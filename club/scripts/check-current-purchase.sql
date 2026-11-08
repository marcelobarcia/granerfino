begin;
do $$
declare a jsonb;b jsonb;bonus text;
begin
 update public.gf_config set stamp_enabled=true,stamp_goal=2,stamp_min_purchase=3000,stamp_repeat=true,
  stamp_reward_kind='discount',stamp_reward_amount=300,stamp_reward_min=3000 where id;
 update public.gf_prizes set weight=case when id in(1,4) then 10 else 0 end;
 update public.gf_prizes set amount=300,min_purchase=3000 where id=1;
 insert into public.gf_wallets(token_hash,name,phone) values('qa5-wallet','QA5 transaction','');
 insert into public.gf_tickets(token_hash,receipt,purchase_amount,test_mode,expires_at) values
  ('qa5-win','QA5-WIN',10000,true,now()+interval '1 day'),('qa5-none','QA5-NONE',10000,true,now()+interval '1 day'),
  ('qa5-live-config','QA5-CONFIG',10000,true,now()+interval '1 day');
 a=public.gf_spin('qa5-win','qa5-wallet',0,'GF-QA5-WIN');
 if a->>'outcome'<>'prize' or not (a->>'allow_same_purchase')::boolean then raise exception 'Immediate prize missing'; end if;
 perform public.gf_redeem('GF-QA5-WIN','QA5-WIN',10000);
 begin perform public.gf_redeem('GF-QA5-WIN','QA5-WIN-AGAIN',10000);raise exception 'Double redemption allowed';
 exception when others then if sqlerrm not like '%ya fue canjeado%' then raise;end if;end;
 b=public.gf_spin('qa5-none','qa5-wallet',.999999,'GF-QA5-NEVER');
 if b->>'outcome'<>'none' or b->>'redeem_code' is not null or not (b->>'stamp_earned')::boolean then raise exception 'No-prize semantics wrong';end if;
 perform public.gf_spin('qa5-none','qa5-wallet',0,'GF-QA5-REPLAY');
 if (select count(*) from public.gf_stamps where ticket_hash='qa5-none')<>1 then raise exception 'Repeated stamp';end if;
 bonus=b#>>'{stamp_bonus,redeem_code}';
 if bonus is null then raise exception 'Missing card completion reward';end if;
 perform public.gf_bonus_redeem(bonus,'QA5-NONE',10000);
 update public.gf_prizes set weight=case when id=2 then 100 else 0 end;
 update public.gf_prizes set min_purchase=3000 where id=2;
 a=public.gf_spin('qa5-live-config','qa5-wallet',.2,'GF-QA5-CONFIG');
 if (a->>'prize_id')::integer<>2 or jsonb_array_length(a->'wheel_prizes')<>1 then raise exception 'Current settings were not used';end if;
end $$;
rollback;
