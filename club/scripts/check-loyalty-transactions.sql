-- Run with a trusted connection. Everything rolls back; no real prizes issued.
begin;
do $$
declare r jsonb; i integer;
begin
 update public.gf_config set stamp_enabled=true,stamp_goal=2,stamp_min_purchase=4000,
  stamp_reward_kind='discount',stamp_reward_title='QA2 snapshot',stamp_reward_amount=111,
  stamp_reward_min=1111,stamp_repeat=true where id;
 for i in 1..8 loop
  insert into public.gf_tickets(token_hash,receipt,purchase_amount,test_mode,expires_at)
   values('qa2param-'||i,'QA2PARAM-'||i,case when i=7 then 3000 else 5000 end,true,now()+interval '1 day');
 end loop;
 r=public.gf_spin('qa2param-1','qa2-param-wallet',0.2,'QA2PARAM-CODE1');
 if (r#>>'{stamp_card,goal}')::integer<>2 then raise exception 'Goal not applied'; end if;
 update public.gf_config set stamp_goal=3,stamp_reward_kind='product',stamp_reward_title='QA2 product',stamp_reward_amount=0,stamp_repeat=false where id;
 r=public.gf_spin('qa2param-2','qa2-param-wallet',0.2,'QA2PARAM-CODE2');
 if r#>>'{stamp_bonus,prize_title}'<>'QA2 snapshot' or (r#>>'{stamp_bonus,prize_amount}')::integer<>111 then raise exception 'Snapshot changed'; end if;
 for i in 3..5 loop r=public.gf_spin('qa2param-'||i,'qa2-param-wallet',0.2,'QA2PARAM-CODE'||i); end loop;
 if r#>>'{stamp_bonus,prize_kind}'<>'product' or r#>>'{stamp_bonus,prize_title}'<>'QA2 product' then raise exception 'Product reward missing'; end if;
 r=public.gf_spin('qa2param-6','qa2-param-wallet',0.2,'QA2PARAM-CODE6');
 if (r->>'stamp_earned')::boolean then raise exception 'Non-repeating card repeated'; end if;
 r=public.gf_spin('qa2param-7','qa2-min-wallet',0.2,'QA2PARAM-CODE7');
 if (r->>'stamp_earned')::boolean then raise exception 'Minimum purchase not enforced'; end if;
 update public.gf_config set stamp_enabled=false where id;
 r=public.gf_spin('qa2param-8','qa2-disabled-wallet',0.2,'QA2PARAM-CODE8');
 if (r->>'stamp_earned')::boolean then raise exception 'Disabled program awarded a stamp'; end if;
 if (select count(*) from public.gf_bonus_rewards where wallet_hash='qa2-param-wallet')<>2 then raise exception 'Unexpected bonus count'; end if;
end $$;
rollback;
