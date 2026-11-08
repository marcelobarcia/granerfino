create or replace function public.gf_settings(p_config jsonb,p_prizes jsonb) returns void
language plpgsql security invoker set search_path='' as $$
declare p jsonb;
begin
 perform 1 from public.gf_config where id for update;
 if jsonb_array_length(p_prizes) not in (3,4,5) or (select count(distinct (value->>'id')::integer) from jsonb_array_elements(p_prizes))<>jsonb_array_length(p_prizes) then raise exception 'Revisá los premios'; end if;
 if not exists(select 1 from jsonb_array_elements(p_prizes) x where (x->>'id')::integer<>4 and (x->>'weight')::integer>0 and (x->>'amount')::integer<=(p_config->>'daily_budget')::integer and (x->>'min_purchase')::integer<=(p_config->>'min_purchase')::integer) then raise exception 'Debe existir un premio habilitado desde el mínimo para girar y dentro del presupuesto'; end if;
 update public.gf_config set test_mode=(p_config->>'test_mode')::boolean,min_purchase=(p_config->>'min_purchase')::integer,
  validity_days=(p_config->>'validity_days')::integer,daily_budget=(p_config->>'daily_budget')::integer,
  stamp_enabled=(p_config->>'stamp_enabled')::boolean,stamp_goal=(p_config->>'stamp_goal')::integer,
  stamp_min_purchase=(p_config->>'stamp_min_purchase')::integer,stamp_repeat=(p_config->>'stamp_repeat')::boolean,
  stamp_reward_kind=p_config->>'stamp_reward_kind',stamp_reward_title=p_config->>'stamp_reward_title',
  stamp_reward_amount=(p_config->>'stamp_reward_amount')::integer,stamp_reward_min=(p_config->>'stamp_reward_min')::integer,
  stamp_reward_days=(p_config->>'stamp_reward_days')::integer,updated_at=now() where id;
 for p in select * from jsonb_array_elements(p_prizes) loop
  if (p->>'id')::integer not in (1,2,3,4,5) then raise exception 'Premio no válido'; end if;
  update public.gf_prizes set amount=(p->>'amount')::integer,min_purchase=(p->>'min_purchase')::integer,
   weight=(p->>'weight')::integer,title=p->>'title',active=true where id=(p->>'id')::integer;
 end loop;
end $$;



insert into public.gf_prizes(id,title,amount,min_purchase,weight,kind) select 5,'$700 de descuento',700,greatest(700,min_purchase),20,'discount' from public.gf_config where id on conflict(id) do nothing;
