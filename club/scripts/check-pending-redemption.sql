begin;
do $$
declare r jsonb;p jsonb;
begin
 update public.gf_config set stamp_enabled=false where id;
 update public.gf_prizes set weight=case when id in(1,4) then 10 else 0 end;
 update public.gf_prizes set min_purchase=3000 where id=1;
 insert into public.gf_tickets(token_hash,receipt,purchase_amount,test_mode,expires_at) values
 ('qa7-pending','QA7-PENDING',3000,true,now()+interval '1 day'),('qa7-impossible','QA7-IMPOSSIBLE',3000,true,now()+interval '1 day');
 r=public.gf_spin('qa7-pending','qa7-anonymous',0,'GF-QA7-AB12');
 if jsonb_array_length(r->'wheel_prizes')<>2 or r->>'outcome'<>'prize' then raise exception 'Entry purchase has no winning option';end if;
 p=public.gf_pending_prizes(true,'AB12',0,25);
 if (p->>'total')::integer<>1 or not (p#>>'{items,0,quick_redeem}')::boolean then raise exception 'Prize missing from quick redemption';end if;
 if p#>>'{items,0,wallet_hash}' is not null then raise exception 'Private token leaked';end if;
 perform public.gf_redeem('GF-QA7-AB12','QA7-PENDING',3000);
 p=public.gf_pending_prizes(true,'AB12',0,25);
 if (p->>'total')::integer<>0 then raise exception 'Redeemed prize still pending';end if;
 update public.gf_prizes set min_purchase=7000 where id=1;
 begin
  perform public.gf_spin('qa7-impossible','qa7-anonymous',0,'GF-QA7-IMPOSSIBLE');
  raise exception 'Forced losing spin was allowed';
 exception when others then if sqlerrm not like '%No hay premios habilitados%' then raise;end if;end;
 if (select spun_at from public.gf_tickets where token_hash='qa7-impossible') is not null then raise exception 'Rejected spin was consumed';end if;
end $$;
rollback;
