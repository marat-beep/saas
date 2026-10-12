-- ============================================================
-- 3DMP Service · 0216_ref_standards.sql
-- Стандартные справочники: допуски IT (ГОСТ 25346), посадки (ГОСТ 25347),
-- метрические резьбы (ГОСТ 24705), крепёж (ГОСТ 7798/5915/11371), формулы.
-- Идемпотентно. Зависит от 0001..0215.
-- ============================================================

-- ---------- Допуски IT (мкм), ГОСТ 25346 ----------
create table if not exists public.app_ref_tolerances (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  size_from numeric not null, size_to numeric not null,
  it_grade text not null, value_um integer not null,
  created_at timestamptz not null default now(),
  unique (tenant_id, size_from, size_to, it_grade)
);
alter table public.app_ref_tolerances enable row level security;

insert into public.app_ref_tolerances (tenant_id, size_from, size_to, it_grade, value_um)
select null, v.a, v.b, v.g, v.val from (values
 (0,3,'IT5',4),(0,3,'IT6',6),(0,3,'IT7',10),(0,3,'IT8',14),(0,3,'IT9',25),(0,3,'IT10',40),(0,3,'IT11',60),(0,3,'IT12',100),
 (3,6,'IT5',5),(3,6,'IT6',8),(3,6,'IT7',12),(3,6,'IT8',18),(3,6,'IT9',30),(3,6,'IT10',48),(3,6,'IT11',75),(3,6,'IT12',120),
 (6,10,'IT5',6),(6,10,'IT6',9),(6,10,'IT7',15),(6,10,'IT8',22),(6,10,'IT9',36),(6,10,'IT10',58),(6,10,'IT11',90),(6,10,'IT12',150),
 (10,18,'IT5',8),(10,18,'IT6',11),(10,18,'IT7',18),(10,18,'IT8',27),(10,18,'IT9',43),(10,18,'IT10',70),(10,18,'IT11',110),(10,18,'IT12',180),
 (18,30,'IT5',9),(18,30,'IT6',13),(18,30,'IT7',21),(18,30,'IT8',33),(18,30,'IT9',52),(18,30,'IT10',84),(18,30,'IT11',130),(18,30,'IT12',210),
 (30,50,'IT5',11),(30,50,'IT6',16),(30,50,'IT7',25),(30,50,'IT8',39),(30,50,'IT9',62),(30,50,'IT10',100),(30,50,'IT11',160),(30,50,'IT12',250),
 (50,80,'IT5',13),(50,80,'IT6',19),(50,80,'IT7',30),(50,80,'IT8',46),(50,80,'IT9',74),(50,80,'IT10',120),(50,80,'IT11',190),(50,80,'IT12',300),
 (80,120,'IT5',15),(80,120,'IT6',22),(80,120,'IT7',35),(80,120,'IT8',54),(80,120,'IT9',87),(80,120,'IT10',140),(80,120,'IT11',220),(80,120,'IT12',350),
 (120,180,'IT5',18),(120,180,'IT6',25),(120,180,'IT7',40),(120,180,'IT8',63),(120,180,'IT9',100),(120,180,'IT10',160),(120,180,'IT11',250),(120,180,'IT12',400),
 (180,250,'IT5',20),(180,250,'IT6',29),(180,250,'IT7',46),(180,250,'IT8',72),(180,250,'IT9',115),(180,250,'IT10',185),(180,250,'IT11',290),(180,250,'IT12',460),
 (250,315,'IT5',23),(250,315,'IT6',32),(250,315,'IT7',52),(250,315,'IT8',81),(250,315,'IT9',130),(250,315,'IT10',210),(250,315,'IT11',320),(250,315,'IT12',520),
 (315,400,'IT5',25),(315,400,'IT6',36),(315,400,'IT7',57),(315,400,'IT8',89),(315,400,'IT9',140),(315,400,'IT10',230),(315,400,'IT11',360),(315,400,'IT12',570),
 (400,500,'IT5',27),(400,500,'IT6',40),(400,500,'IT7',63),(400,500,'IT8',97),(400,500,'IT9',155),(400,500,'IT10',250),(400,500,'IT11',400),(400,500,'IT12',630)
) v(a,b,g,val)
where not exists (select 1 from public.app_ref_tolerances t where t.tenant_id is null and t.size_from=v.a and t.size_to=v.b and t.it_grade=v.g);

-- ---------- Посадки (значения в мм), ГОСТ 25347 ----------
insert into public.app_ref_fits (tenant_id, nominal, designation, kind, hole_dev, shaft_dev, clearance_max, clearance_min, note)
select null, v.n, v.d, v.k, v.h, v.s, v.cm, v.cn, v.note from (values
 (10,'H7/h6','clearance','+15/0','0/-9',0.024,0.000,'Плотная посадка, центрирование.'),
 (10,'H7/g6','clearance','+15/0','-5/-14',0.029,0.005,'Лёгкое скольжение.'),
 (10,'H7/f7','clearance','+15/0','-13/-28',0.043,0.013,'Скользящая, смазка.'),
 (10,'H7/k6','transition','+15/0','+10/+1',0.014,-0.010,'Напряжённая (шпонки, зубчатые).'),
 (10,'H7/p6','interference','+15/0','+24/+15',-0.000,-0.024,'Лёгкопрессовая (втулки).'),
 (10,'H8/h7','clearance','+22/0','0/-15',0.037,0.000,'Ходовая.'),
 (10,'H11/h11','clearance','+90/0','0/-90',0.180,0.000,'Грубая подвижная.'),
 (10,'F8/h6','clearance','+35/+13','0/-9',0.044,0.013,'Скользящая с зазором.'),
 (20,'H7/h6','clearance','+21/0','0/-13',0.034,0.000,'Плотная.'),
 (20,'H7/g6','clearance','+21/0','-7/-20',0.041,0.007,'Скользящая.'),
 (20,'H7/f7','clearance','+21/0','-20/-41',0.062,0.020,'Смазка.'),
 (20,'H7/k6','transition','+21/0','+15/+2',0.019,-0.015,'Напряжённая.'),
 (20,'H7/p6','interference','+21/0','+35/+22',-0.001,-0.035,'Прессовая лёгкая.'),
 (20,'H7/n6','interference','+21/0','+28/+15',0.006,-0.028,'Глухопрессовая.'),
 (20,'H8/h7','clearance','+33/0','0/-21',0.054,0.000,'Ходовая.'),
 (20,'H11/h11','clearance','+130/0','0/-130',0.260,0.000,'Грубая.'),
 (50,'H7/h6','clearance','+25/0','0/-16',0.041,0.000,'Плотная.'),
 (50,'H7/g6','clearance','+25/0','-9/-25',0.050,0.009,'Скользящая.'),
 (50,'H7/k6','transition','+25/0','+18/+2',0.023,-0.018,'Напряжённая.'),
 (50,'H7/p6','interference','+25/0','+42/+26',-0.001,-0.042,'Прессовая.'),
 (50,'H8/h7','clearance','+39/0','0/-25',0.064,0.000,'Ходовая.'),
 (50,'H11/h11','clearance','+160/0','0/-160',0.320,0.000,'Грубая.'),
 (80,'H7/h6','clearance','+30/0','0/-19',0.049,0.000,'Плотная.'),
 (80,'H7/g6','clearance','+30/0','-10/-29',0.059,0.010,'Скользящая.'),
 (80,'H7/k6','transition','+30/0','+21/+2',0.028,-0.021,'Напряжённая.'),
 (80,'H7/p6','interference','+30/0','+51/+32',-0.002,-0.051,'Прессовая.'),
 (80,'H8/h7','clearance','+46/0','0/-30',0.076,0.000,'Ходовая.'),
 (80,'H11/h11','clearance','+190/0','0/-190',0.380,0.000,'Грубая.')
) v(n,d,k,h,s,cm,cn,note)
where not exists (select 1 from public.app_ref_fits f where f.tenant_id is null and f.nominal=v.n and f.designation=v.d);

-- ---------- Метрические резьбы, ГОСТ 24705 ----------
create table if not exists public.app_ref_threads (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  designation text not null, pitch numeric, d2 numeric, d1 numeric, predrill numeric, note text,
  created_at timestamptz not null default now(),
  unique (tenant_id, designation)
);
alter table public.app_ref_threads enable row level security;

insert into public.app_ref_threads (tenant_id, designation, pitch, d2, d1, predrill, note)
select null, v.d, v.p, v.d2, v.d1, v.pre, v.note from (values
 ('М2',0.4,1.740,1.567,1.6,'Сверло Ø1.6.'),
 ('М2.5',0.45,2.208,2.013,2.05,'Сверло Ø2.05.'),
 ('М3',0.5,2.675,2.459,2.5,'Сверло Ø2.5.'),
 ('М4',0.7,3.545,3.242,3.3,'Сверло Ø3.3.'),
 ('М5',0.8,4.480,4.134,4.2,'Сверло Ø4.2.'),
 ('М6',1.0,5.350,4.917,5.0,'Сверло Ø5.0.'),
 ('М8',1.25,7.188,6.647,6.8,'Сверло Ø6.8.'),
 ('М10',1.5,9.026,8.376,8.5,'Сверло Ø8.5.'),
 ('М12',1.75,10.863,10.106,10.2,'Сверло Ø10.2.'),
 ('М14',2.0,12.701,11.835,12.0,'Сверло Ø12.0.'),
 ('М16',2.0,14.701,13.835,14.0,'Сверло Ø14.0.'),
 ('М18',2.5,16.376,15.294,15.5,'Сверло Ø15.5.'),
 ('М20',2.5,18.376,17.294,17.5,'Сверло Ø17.5.'),
 ('М22',2.5,20.376,19.294,19.5,'Сверло Ø19.5.'),
 ('М24',3.0,22.051,20.752,21.0,'Сверло Ø21.0.'),
 ('М27',3.0,25.051,23.752,24.0,'Сверло Ø24.0.'),
 ('М30',3.5,27.727,26.211,26.5,'Сверло Ø26.5.'),
 ('М36',4.0,33.402,31.670,32.0,'Сверло Ø32.0.')
) v(d,p,d2,d1,pre,note)
where not exists (select 1 from public.app_ref_threads t where t.tenant_id is null and t.designation=v.d);

-- ---------- Крепёж: расширение ----------
insert into public.app_ref_fasteners (tenant_id, kind, standard, size, material, coating, note)
select null, v.k, v.std, v.sz, v.mat, v.coat, v.note from (values
 ('Болт','ГОСТ 7798-70','М6×20','Сталь 8.8','цинк','Класс точности B; кл. прочности 5.8/8.8.'),
 ('Болт','ГОСТ 7798-70','М10×30','Сталь 8.8','цинк','Vc/Vf по стали; ключ по ГОСТ.'),
 ('Болт','ГОСТ 7798-70','М16×60','Сталь 10.9','оксид','Высоконагруженный.'),
 ('Болт','ГОСТ 7805-70','М12×40','Сталь 8.8','—','С шестигранной головкой уменьш.'),
 ('Гайка','ГОСТ 5915-70','М6','Сталь 8','цинк','Класс прочности 8.'),
 ('Гайка','ГОСТ 5915-70','М10','Сталь 8','цинк','—'),
 ('Гайка','ГОСТ 5915-70','М16','Сталь 10','оксид','—'),
 ('Гайка','ГОСТ 5931-70','М12','Сталь 8','—','Высокая.'),
 ('Шайба','ГОСТ 11371-78','Ø10.5','Сталь','цинк','Плоская.'),
 ('Шайба','ГОСТ 11371-78','Ø16.5','Сталь','—','Плоская.'),
 ('Шайба пружинная','ГОСТ 6402-70','Ø10','Сталь 65Г','—','Гровер.'),
 ('Винт','ГОСТ 1491-80','М6×20','Сталь 8.8','цинк','С потайной головкой.'),
 ('Винт установочный','ГОСТ 1476-93','М8×10','Сталь 45','оксид','Цилиндр. без головки.'),
 ('Шпилька','ГОСТ 22032-76','М10×60','Сталь 8.8','цинк','Ввинчиваемый конец.'),
 ('Болт кл. прочности','ГОСТ Р ИСО 898-1','5.8','Сталь','—','σв=500 МПа, σт=400.'),
 ('Болт кл. прочности','ГОСТ Р ИСО 898-1','8.8','Сталь','—','σв=800 МПа, σт=640.'),
 ('Болт кл. прочности','ГОСТ Р ИСО 898-1','10.9','Сталь','—','σв=1040 МПа, σт=940.'),
 ('Болт кл. прочности','ГОСТ Р ИСО 898-1','12.9','Сталь','—','σв=1220 МПа, σт=1100.')
) v(k,std,sz,mat,coat,note)
where not exists (select 1 from public.app_ref_fasteners f where f.tenant_id is null and f.kind=v.k and coalesce(f.size,'')=v.sz);

-- ---------- RPC новых справочников ----------
create or replace function public.app_ref_tolerances_list(p_token uuid, p_grade text default null)
returns table (id uuid, size_from numeric, size_to numeric, it_grade text, value_um integer)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select t.id, t.size_from, t.size_to, t.it_grade, t.value_um
    from public.app_ref_tolerances t
   where (t.tenant_id is null or t.tenant_id = ten or adm)
     and (p_grade is null or t.it_grade = p_grade)
   order by t.size_from, t.it_grade;
end $$;

create or replace function public.app_ref_threads_list(p_token uuid, p_q text default null)
returns table (id uuid, designation text, pitch numeric, d2 numeric, d1 numeric, predrill numeric, note text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; q text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  q := lower(coalesce(trim(p_q),''));
  return query select t.id, t.designation, t.pitch, t.d2, t.d1, t.predrill, t.note
    from public.app_ref_threads t
   where (t.tenant_id is null or t.tenant_id = ten or adm)
     and (q = '' or lower(t.designation) like '%'||q||'%')
   order by t.pitch;
end $$;

-- ---------- БЗ: стандарты ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select null, v.category, v.question, v.answer, v.tags
from (values
 ('Стандарты','Допуски IT и квалитеты (ГОСТ 25346)','Квалитеты IT5-IT12 по интервалам размеров. Пример (18-30 мм): IT6=13, IT7=21, IT8=33, IT11=130 мкм. Отверстие H7 = +IT7/0; вал h6 = 0/-IT6. Таблица IT — в справочнике «Допуски IT».','допуск IT квалитет 25346 H7 h6 мкм'),
 ('Стандарты','Посадки (ГОСТ 25347): зазор/переход/натяг','H7/h6 — плотная; H7/g6, H7/f7, H8/h7, H11/h11 — с зазором; H7/k6, H7/m6, H7/n6 — переходные; H7/p6, H7/r6, H7/s6 — с натягом. См. «Посадки ISO 286» в справочнике.','посадка H7 h6 g6 k6 p6 зазор натяг переходная'),
 ('Стандарты','Метрическая резьба и предсверливание (ГОСТ 24705)','Шаг основной резьбы и диаметры d2/d1: М6×1, М8×1.25, М10×1.5, М12×1.75, М16×2, М20×2.5. Предсверливание: М3→2.5, М4→3.3, М5→4.2, М6→5.0, М8→6.8, М10→8.5, М12→10.2, М16→14.0. См. справочник «Резьбы».','резьба метрическая шаг d2 d1 предсверливание 24705'),
 ('Стандарты','Крепёж и классы прочности (ГОСТ)','Болты ГОСТ 7798-70, гайки ГОСТ 5915-70, шайбы ГОСТ 11371-78, гровер ГОСТ 6402. Классы прочности 5.8 (σв 500), 8.8 (800), 10.9 (1040), 12.9 (1220 МПа).','крепёж болт гайка шайба ГОСТ класс прочности 8.8 10.9'),
 ('Обработка','Формулы массы заготовки (круг/прямоуг./труба)','Круг: m=π·D²/4·ρ·L (D,L в м). Прямоуг.: m=A·B·ρ·L. Труба: m=π·(D²−d²)/4·ρ·L. ρ стали 7850 кг/м³ (7.85 г/см³).','масса заготовки формула круг труба прямоугольник ρ')
) v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge k where k.tenant_id is null and k.question = v.question);

grant execute on function public.app_ref_tolerances_list(uuid,text) to anon, authenticated;
grant execute on function public.app_ref_threads_list(uuid,text) to anon, authenticated;
