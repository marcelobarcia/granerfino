CREATE OR REPLACE FUNCTION public.gf_assisted_purchase(p_wallet text, p_receipt text, p_amount integer, p_token text, p_random double precision, p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare c public.gf_config;
begin
 if not exists(select 1 from public.gf_wallets where token_hash=p_wallet) then raise exception 'Miembro no encontrado'; end if;
 select * into c from public.gf_config where id;
 if p_amount<c.min_purchase then raise exception 'La compra no alcanza el mínimo para girar'; end if;
 insert into public.gf_tickets(token_hash,receipt,purchase_amount,test_mode,expires_at)
 values(p_token,trim(p_receipt),p_amount,c.test_mode,now()+interval '7 days');
 return public.gf_spin(p_token,p_wallet,p_random,p_code);
end $function$

CREATE OR REPLACE FUNCTION public.gf_finish_recovery(p_token text, p_pin text, p_salt text, p_session text)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare r public.gf_recovery_links;
begin
 select * into r from public.gf_recovery_links where token_hash=p_token for update;
 if not found or r.used_at is not null or r.expires_at<now() then raise exception 'Este enlace venció o ya fue utilizado. Pedí uno nuevo en la tienda'; end if;
 update public.gf_wallets set customer_pin_hash=p_pin,customer_pin_salt=p_salt,legacy_access_enabled=false where token_hash=r.wallet_hash;
 delete from public.gf_customer_sessions where wallet_hash=r.wallet_hash;
 update public.gf_recovery_links set used_at=now() where wallet_hash=r.wallet_hash and used_at is null;
 insert into public.gf_customer_sessions(token_hash,wallet_hash,expires_at) values(p_session,r.wallet_hash,now()+interval '180 days');
end $function$

CREATE OR REPLACE FUNCTION public.gf_make_recovery(p_wallet text, p_token text)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
 perform 1 from public.gf_wallets where token_hash=p_wallet for update;
 if not found then raise exception 'Miembro no encontrado'; end if;
 update public.gf_recovery_links set used_at=now() where wallet_hash=p_wallet and used_at is null;
 insert into public.gf_recovery_links(token_hash,wallet_hash,expires_at) values(p_token,p_wallet,now()+interval '15 minutes');
end $function$

CREATE OR REPLACE FUNCTION public.gf_members(p_search text, p_mode boolean, p_marketing boolean, p_page integer, p_size integer)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$
 with matched as (
  select w.* from public.gf_wallets w
  where (p_search='' or strpos(lower(w.name),lower(p_search))>0 or strpos(w.phone,p_search)>0 or strpos(lower(w.member_code),lower(p_search))>0)
   and (not p_marketing or w.marketing)
   and ((w.assisted and w.registration_test_mode=p_mode) or exists(select 1 from public.gf_tickets t where t.wallet_hash=w.token_hash and t.test_mode=p_mode))
 ), paged as (
  select * from matched order by created_at desc,member_id limit least(greatest(p_size,1),500) offset greatest(p_page,0)*least(greatest(p_size,1),500)
 ), items as (
  select p.member_id,p.member_code,p.assisted,p.name,p.phone,p.marketing,p.created_at,
   (select count(*) from public.gf_tickets t where t.wallet_hash=p.token_hash and t.test_mode=p_mode and t.spun_at is not null) as purchases,
   (select count(*) from public.gf_stamps s join public.gf_cards c on c.id=s.card_id where c.wallet_hash=p.token_hash and c.test_mode=p_mode) as stamps,
   ((select count(*) from public.gf_tickets t where t.wallet_hash=p.token_hash and t.test_mode=p_mode and t.spun_at is not null and not t.revoked and t.redeemed_at is null and t.prize_expires_at>now())+
    (select count(*) from public.gf_bonus_rewards b where b.wallet_hash=p.token_hash and b.test_mode=p_mode and not b.revoked and b.redeemed_at is null and b.prize_expires_at>now())) as available_prizes
  from paged p
 ) select jsonb_build_object('total',(select count(*) from matched),'items',coalesce((select jsonb_agg(to_jsonb(i) order by i.created_at desc,i.member_id) from items i),'[]'::jsonb));
$function$
revoke all on function public.gf_make_recovery(text,text),public.gf_finish_recovery(text,text,text,text),public.gf_assisted_purchase(text,text,integer,text,double precision,text),public.gf_members(text,boolean,boolean,integer,integer) from public,anon,authenticated;
grant execute on function public.gf_make_recovery(text,text),public.gf_finish_recovery(text,text,text,text),public.gf_assisted_purchase(text,text,integer,text,double precision,text),public.gf_members(text,boolean,boolean,integer,integer) to service_role;
