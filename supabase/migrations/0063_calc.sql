-- ============================================================
-- 3DMP Service · 0063_calc.sql  (v41 — ЭПИК F: 8 мини-сервисов/калькуляторов)
-- Калькуляторы: масса проката, режимы резания, ISO 286, нормочас ЧПУ,
-- себестоимость детали, децимальные/обозначения, конвертеры, подбор технологии.
-- Сохранение расчётов (app_calc_saves) с привязкой к заявке.
-- База знаний. Зависит от 0001..0062.
-- ============================================================

create table if not exists public.app_calc_saves (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  kind          text not null,   -- mass|cutting|iso|cnc|cost|decimal|convert|tech
  title         text,
  input         jsonb,
  result        jsonb,
  ref           text,
  order_id      uuid references public.app_orders (id) on delete set null,
  created_login text,
  created_at    timestamptz not null default now()
);
create index if not exists app_calc_saves_idx on public.app_calc_saves (tenant_id, kind, created_at desc);
alter table public.app_calc_saves enable row level security;

-- ---------- 1. Масса проката ----------
create or replace function public.app_calc_mass(
  p_token uuid, p_profile text, p_a numeric, p_b numeric default 0, p_c numeric default 0,
  p_len numeric default 0, p_density numeric default 7.85, p_qty numeric default 1)
returns table (area_mm2 numeric, volume_mm3 numeric, mass_kg numeric, mass_total_kg numeric)
language plpgsql security definer set search_path = public
as $$
declare a numeric; area numeric; vol numeric; m numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  if coalesce(p_a,0) <= 0 then raise exception 'Укажите размер сечения'; end if;
  area := case lower(coalesce(p_profile,'round'))
    when 'round'  then pi()*p_a*p_a/4
    when 'square' then p_a*p_a
    when 'rect'   then p_a*coalesce(p_b,0)
    when 'pipe'   then pi()*(p_a*p_a - greatest(p_a-2*coalesce(p_c,0),0)^2)/4
    when 'sheet'  then p_a*coalesce(p_b,0)
    when 'hex'    then sqrt(3)/2*p_a*p_a
    else pi()*p_a*p_a/4 end;
  vol := area * coalesce(p_len,0);
  m := vol * coalesce(p_density,7.85) / 1000000.0;
  return query select round(area,2), round(vol,2), round(m,4), round(m*coalesce(p_qty,1),4);
end $$;

-- ---------- 2. Режимы резания ----------
create or replace function public.app_calc_cutting(
  p_token uuid, p_vc numeric, p_d numeric, p_fz numeric, p_z int default 1,
  p_ap numeric default 0, p_ae numeric default 0, p_kc numeric default 2000)
returns table (n_rpm numeric, feed_rev numeric, vf_mm_min numeric, mrr_cm3_min numeric, pc_kw numeric)
language plpgsql security definer set search_path = public
as $$
declare n numeric; vf numeric; mrr numeric; pc numeric; fz numeric; z int;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  if coalesce(p_vc,0) <= 0 or coalesce(p_d,0) <= 0 then raise exception 'Укажите Vc и диаметр'; end if;
  fz := coalesce(p_fz,0); z := greatest(coalesce(p_z,1),1);
  n := 1000.0*p_vc/(pi()*p_d);
  vf := fz*z*n;
  mrr := coalesce(p_ap,0)*coalesce(p_ae,0)*vf/1000.0;
  pc := coalesce(p_ap,0)*coalesce(p_ae,0)*vf*coalesce(p_kc,2000)/(60.0*1000000.0);
  return query select round(n,0), round(fz*z,3), round(vf,1), round(mrr,2), round(pc,2);
end $$;

-- ---------- 3. ISO 286 (посадки) ----------
create or replace function public.app_calc_iso(
  p_token uuid, p_nominal numeric, p_hole_es numeric, p_hole_ei numeric,
  p_shaft_es numeric, p_shaft_ei numeric)
returns table (hole_max numeric, hole_min numeric, shaft_max numeric, shaft_min numeric,
               clearance_min numeric, clearance_max numeric, fit text)
language plpgsql security definer set search_path = public
as $$
declare hmax numeric; hmin numeric; smax numeric; smin numeric; cmin numeric; cmax numeric; ft text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  hmax := p_nominal + coalesce(p_hole_es,0); hmin := p_nominal + coalesce(p_hole_ei,0);
  smax := p_nominal + coalesce(p_shaft_es,0); smin := p_nominal + coalesce(p_shaft_ei,0);
  cmin := hmin - smax; cmax := hmax - smin;
  ft := case when cmin >= 0 then 'зазор' when cmax <= 0 then 'натяг' else 'переходная' end;
  return query select round(hmax,4), round(hmin,4), round(smax,4), round(smin,4), round(cmin,4), round(cmax,4), ft;
end $$;

-- ---------- 4. Нормочас ЧПУ ----------
create or replace function public.app_calc_cnc(
  p_token uuid, p_machine_price numeric, p_life_years numeric default 7, p_hours_year numeric default 2000,
  p_power_kw numeric default 10, p_energy_price numeric default 6, p_fot_rate numeric default 0,
  p_tools_rate numeric default 0, p_overhead_pct numeric default 15)
returns table (amort numeric, energy numeric, fot numeric, tools numeric, direct numeric, overhead numeric, rate numeric)
language plpgsql security definer set search_path = public
as $$
declare am numeric; en numeric; ft numeric; toc numeric; dr numeric; ov numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  am := case when coalesce(p_life_years,0)*coalesce(p_hours_year,0) > 0
             then coalesce(p_machine_price,0)/(p_life_years*p_hours_year) else 0 end;
  en := coalesce(p_power_kw,0)*coalesce(p_energy_price,0);
  ft := coalesce(p_fot_rate,0); toc := coalesce(p_tools_rate,0);
  dr := am + en + ft + toc;
  ov := dr*coalesce(p_overhead_pct,0)/100.0;
  return query select round(am,2), round(en,2), round(ft,2), round(toc,2), round(dr,2), round(ov,2), round(dr+ov,2);
end $$;

-- ---------- 5. Себестоимость детали ----------
create or replace function public.app_calc_cost(
  p_token uuid, p_material_cost numeric default 0, p_work_hours numeric default 0,
  p_rate numeric default 0, p_overhead_pct numeric default 15, p_qty numeric default 1)
returns table (material numeric, work numeric, overhead numeric, total numeric, per_unit numeric)
language plpgsql security definer set search_path = public
as $$
declare mat numeric; wrk numeric; ov numeric; tot numeric; q numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  mat := coalesce(p_material_cost,0);
  wrk := coalesce(p_work_hours,0)*coalesce(p_rate,0);
  ov := (mat+wrk)*coalesce(p_overhead_pct,0)/100.0;
  tot := mat+wrk+ov;
  q := greatest(coalesce(p_qty,1),1);
  return query select round(mat,2), round(wrk,2), round(ov,2), round(tot,2), round(tot/q,2);
end $$;

-- ---------- 6. Децимальные обозначения ----------
create or replace function public.app_calc_decimal(
  p_token uuid, p_code text, p_doc_number text, p_litera text default null)
returns table (designation text)
language plpgsql security definer set search_path = public
as $$
declare code text; num text; lit text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  code := upper(coalesce(nullif(trim(p_code),''),'АБВГ'));
  num  := lpad(regexp_replace(coalesce(p_doc_number,'0'), '\D', '', 'g'), 6, '0');
  lit  := nullif(trim(coalesce(p_litera,'')),'');
  return query select code || '.' || num || coalesce('-'||upper(lit),'');
end $$;

-- ---------- 7. Конвертеры ----------
create or replace function public.app_calc_convert(p_token uuid, p_kind text, p_value numeric)
returns table (result numeric, unit text, formula text)
language plpgsql security definer set search_path = public
as $$
declare r numeric; u text; f text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  case lower(coalesce(p_kind,''))
    when 'mm_in'   then r := p_value/25.4;          u := 'дюйм'; f := 'мм / 25.4';
    when 'in_mm'   then r := p_value*25.4;          u := 'мм';   f := 'дюйм × 25.4';
    when 'hb_sigma' then r := p_value*3.38;         u := 'МПа';  f := 'HB × 3.38 (σв)';
    when 'sigma_hb' then r := p_value/3.38;         u := 'HB';   f := 'σв / 3.38';
    when 'kg_lb'   then r := p_value*2.20462;       u := 'lb';   f := 'кг × 2.20462';
    when 'lb_kg'   then r := p_value/2.20462;       u := 'кг';   f := 'lb / 2.20462';
    when 'n_kgf'   then r := p_value/9.80665;       u := 'кгс';  f := 'Н / 9.80665';
    when 'kgf_n'   then r := p_value*9.80665;       u := 'Н';    f := 'кгс × 9.80665';
    when 'kw_hp'   then r := p_value*1.34102;       u := 'л.с.'; f := 'кВт × 1.34102';
    when 'hp_kw'   then r := p_value/1.34102;       u := 'кВт';  f := 'л.с. / 1.34102';
    when 'grad_rad' then r := p_value*pi()/180.0;   u := 'рад';  f := 'град × π/180';
    when 'rad_grad' then r := p_value*180.0/pi();   u := 'град'; f := 'рад × 180/π';
    else raise exception 'Неизвестный тип конвертации: %', p_kind;
  end case;
  return query select round(r,6), u, f;
end $$;

-- ---------- 8. Подбор технологии ----------
create or replace function public.app_calc_tech(p_token uuid, p_material text, p_feature text)
returns table (recommendation text, note text, source text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select r.recommendation, r.note, 'правило'::text
    from public.app_tech_rules r
    where (r.tenant_id is null or r.tenant_id = ten)
      and (r.material is null or r.material = '*' or r.material = p_material or lower(coalesce(r.material,'')) = lower(coalesce(p_material,'')))
      and (r.feature  is null or r.feature  = '*' or r.feature  = p_feature  or lower(coalesce(r.feature,''))  = lower(coalesce(p_feature,'')))
    order by (case when lower(coalesce(r.material,''))=lower(coalesce(p_material,'')) then 0 else 1 end),
             (case when lower(coalesce(r.feature,''))=lower(coalesce(p_feature,'')) then 0 else 1 end)
    limit 5;
  if not found then
    return query
      select k.answer, k.question, 'база знаний'::text
      from public.app_knowledge k
      where (k.tenant_id is null or k.tenant_id = ten)
        and (lower(k.question) like '%'||lower(coalesce(p_material,''))||'%'
          or lower(coalesce(k.tags,'')) like '%'||lower(coalesce(p_feature,''))||'%')
      limit 3;
  end if;
end $$;

-- ---------- Сохранение расчётов ----------
create or replace function public.app_calc_save(p_token uuid, p_kind text, p_title text,
  p_input jsonb, p_result jsonb, p_ref text default null, p_order_id uuid default null)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; ulogin text; cid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.ulogin into ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_kind),'') = '' then raise exception 'Укажите тип расчёта'; return; end if;
  insert into public.app_calc_saves (tenant_id, kind, title, input, result, ref, order_id, created_login)
  values (ten, lower(trim(p_kind)), nullif(trim(p_title),''), p_input, p_result, nullif(trim(p_ref),''), p_order_id, ulogin)
  returning id into cid;
  return query select cid, 'Расчёт сохранён';
end $$;

create or replace function public.app_calc_list(p_token uuid, p_kind text default null, p_q text default null)
returns table (id uuid, kind text, title text, ref text, order_number text, result jsonb, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select c.id, c.kind, c.title, c.ref, o.number, c.result, c.created_at
    from public.app_calc_saves c
    left join public.app_orders o on o.id = c.order_id
    where (urole='admin' or c.tenant_id = ten)
      and (coalesce(p_kind,'')='' or c.kind = p_kind)
      and (qq='' or lower(coalesce(c.title,'')) like '%'||qq||'%' or lower(coalesce(c.ref,'')) like '%'||qq||'%')
    order by c.created_at desc;
end $$;

create or replace function public.app_calc_get(p_token uuid, p_id uuid)
returns table (id uuid, kind text, title text, input jsonb, result jsonb, ref text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select c.id, c.kind, c.title, c.input, c.result, c.ref, c.created_at
    from public.app_calc_saves c
    where c.id = p_id and (urole='admin' or c.tenant_id = ten);
end $$;

create or replace function public.app_calc_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_calc_saves where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Расчёт удалён';
end $$;

grant execute on function public.app_calc_mass(uuid,text,numeric,numeric,numeric,numeric,numeric,numeric) to anon, authenticated;
grant execute on function public.app_calc_cutting(uuid,numeric,numeric,numeric,int,numeric,numeric,numeric) to anon, authenticated;
grant execute on function public.app_calc_iso(uuid,numeric,numeric,numeric,numeric,numeric) to anon, authenticated;
grant execute on function public.app_calc_cnc(uuid,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric) to anon, authenticated;
grant execute on function public.app_calc_cost(uuid,numeric,numeric,numeric,numeric,numeric) to anon, authenticated;
grant execute on function public.app_calc_decimal(uuid,text,text,text) to anon, authenticated;
grant execute on function public.app_calc_convert(uuid,text,numeric) to anon, authenticated;
grant execute on function public.app_calc_tech(uuid,text,text) to anon, authenticated;
grant execute on function public.app_calc_save(uuid,text,text,jsonb,jsonb,text,uuid) to anon, authenticated;
grant execute on function public.app_calc_list(uuid,text,text) to anon, authenticated;
grant execute on function public.app_calc_get(uuid,uuid) to anon, authenticated;
grant execute on function public.app_calc_delete(uuid,uuid) to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Мини-сервисы','Какие калькуляторы есть в системе (B34/A1)?',
   'Модуль «Калькуляторы»: масса проката (круг/квадрат/прямоугольник/труба/лист/шестигранник, плотность, количество), режимы резания (Vc→обороты, минутная подача, MRR, мощность), ISO 286 (посадки: предельные размеры, зазор/натяг), нормочас ЧПУ (амортизация+энергия+ФОТ+расходники+накладные), себестоимость детали (материал+работы+накладные), децимальные обозначения (ГОСТ 2.201), конвертеры (мм↔дюйм, HB↔σв, кг↔lb, Н↔кгс, кВт↔л.с.), подбор технологии (по материалу и признаку). Расчёт можно сохранить и привязать к заявке.',
   'калькуляторы масса проката режимы резания ISO 286 нормочас себестоимость децимальные конвертер подбор технологии')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Какие калькуляторы есть в системе (B34/A1)?');
