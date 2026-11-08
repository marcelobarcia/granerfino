-- Apply after schema.sql on a new project, then set a random one-time
-- setup_hash through a trusted admin connection (never commit the token).
insert into public.gf_config(id) values(true);
insert into public.gf_prizes(id,title,amount,min_purchase,weight) values
 (1,'$300 de descuento',300,7000,60),
 (2,'$500 de descuento',500,10000,30),
 (3,'$1.000 de descuento',1000,15000,10);
