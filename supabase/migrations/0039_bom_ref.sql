-- ============================================================
-- 3DMP Service · 0039_bom_ref.sql  (v21.0 — переработка «Спецификации/BOM»)
-- Спецификация из техпроцесса, себестоимость по BOM, связи с операциями/материалами.
-- База знаний. Tenant-изоляция. Зависит от 0001..0038.
-- ============================================================

alter table public.app_bom add column if not exists product_code text;
alter table public.app_bom add column if not exists qty numeric;
alter table public.app_bom add column if not exists status text not null default 'draft'; -- draft | active
alter table public.app_bom add column if not exists source_template_id uuid references public.app_process_templates (id) on delete set null;
alter table public.app_bom_lines add column if not exists operation_id uuid references public.app_operations (id) on delete set null;

-- ---------- Список спецификаций ----------
drop function if exists public.app_bom_list(uuid);
create or replace function public.app_bom_list(p_token uuid)
returns table (id uuid, product text, product_code text, version text, status text, qty numeric,
               order_id uuid, order_number text, source_template_id uuid,
               lines_count bigint, materials_count bigint, norm_hours_sum numeric, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select b.id, b.product, b.product_code, b.version, b.status, b.qty, b.order_id, o.number, b.source_template_id,
           (select count(*) from public.app_bom_lines l where l.bom_id = b.id),
           (select count(*) from public.app_bom_lines l where l.bom_id = b.id and l.item_type='material'),
           coalesce((select sum(l.norm_hours) from public.app_bom_lines l where l.bom_id = b.id),0),
           b.created_at
    from public.app_bom b left join public.app_orders o on o.id = b.order_id
    where (urole='admin' or b.tenant_id = ten)
    order by b.created_at desc;
end $$;

-- ---------- Позиции спецификации (с себестоимостью позиции) ----------
drop function if exists public.app_bom_lines_list(uuid,uuid);
create or replace function public.app_bom_lines_list(p_token uuid, p_bom_id uuid)
returns table (id uuid, seq integer, item_type text, material_id uuid, operation_id uuid, name text,
               qty numeric, unit text, norm_hours numeric, price numeric, cost numeric)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select l.id, l.seq, l.item_type, l.material_id, l.operation_id, l.name, l.qty, l.unit, l.norm_hours,
           case when l.item_type='material' then coalesce(m.price,0) else coalesce(op.base_rate,0) end,
           round(case when l.item_type='material' then coalesce(l.qty,0)*coalesce(m.price,0)
                      else coalesce(l.norm_hours,0)*coalesce(op.base_rate,0) end, 2)
    from public.app_bom_lines l
    join public.app_bom b on b.id = l.bom_id
    left join public.app_materials m on m.id = l.material_id
    left join public.app_operations op on op.id = l.operation_id
    where l.bom_id = p_bom_id and (urole='admin' or b.tenant_id = ten)
    order by l.seq, l.id;
end $$;

-- ---------- Сохранить спецификацию ----------
drop function if exists public.app_bom_save(uuid,uuid,uuid,text,text,jsonb);
create or replace function public.app_bom_save(p_token uuid, p_id uuid, p_order_id uuid, p_product text, p_version text, p_lines jsonb,
  p_product_code text default null, p_qty numeric default null)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ulogin text; ten uuid; bid uuid; ln jsonb; i integer := 0;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_product),'') = '' then raise exception 'Укажите изделие'; end if;

  if p_id is null then
    insert into public.app_bom (tenant_id, order_id, product, product_code, version, qty, created_by, created_login)
    values (ten, p_order_id, trim(p_product), nullif(trim(p_product_code),''), coalesce(nullif(trim(p_version),''),'1'), p_qty, uid, ulogin)
    returning app_bom.id into bid;
  else
    update public.app_bom set order_id = p_order_id, product = trim(p_product),
      product_code = nullif(trim(p_product_code),''), version = coalesce(nullif(trim(p_version),''),'1'),
      qty = p_qty, updated_at = now()
     where id = p_id and (ten is null or tenant_id = ten)
     returning app_bom.id into bid;
    delete from public.app_bom_lines where bom_id = bid;
  end if;

  if p_lines is not null then
    for ln in select * from jsonb_array_elements(p_lines) loop
      i := i + 1;
      insert into public.app_bom_lines (bom_id, seq, item_type, material_id, operation_id, name, qty, unit, norm_hours)
      values (bid, i,
              coalesce(nullif(ln->>'item_type',''),'material'),
              nullif(ln->>'material_id','')::uuid,
              nullif(ln->>'operation_id','')::uuid,
              coalesce(nullif(ln->>'name',''),'—'),
              coalesce((ln->>'qty')::numeric,0),
              nullif(ln->>'unit',''),
              coalesce((ln->>'norm_hours')::numeric,0));
    end loop;
  end if;
  return query select bid, 'Спецификация сохранена';
end $$;

-- ---------- Себестоимость по спецификации ----------
create or replace function public.app_bom_cost(p_token uuid, p_bom_id uuid, p_qty numeric default 1)
returns table (materials_cost numeric, work_cost numeric, total numeric)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; mc numeric; wc numeric; k numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if not exists (select 1 from public.app_bom b where b.id = p_bom_id and (urole='admin' or b.tenant_id = ten)) then
    raise exception 'Спецификация не найдена';
  end if;
  k := greatest(coalesce(p_qty,1), 1);
  select coalesce(sum(coalesce(l.qty,0)*coalesce(m.price,0)),0) into mc
    from public.app_bom_lines l left join public.app_materials m on m.id = l.material_id
    where l.bom_id = p_bom_id and l.item_type='material';
  select coalesce(sum(coalesce(l.norm_hours,0)*coalesce(op.base_rate,0)),0) into wc
    from public.app_bom_lines l left join public.app_operations op on op.id = l.operation_id
    where l.bom_id = p_bom_id and l.item_type='operation';
  materials_cost := round(mc * k, 2);
  work_cost := round(wc * k, 2);
  total := round((materials_cost + work_cost) * 1.15, 2); -- +15% накладные (как в экономике)
  return next;
end $$;

-- ---------- Создать спецификацию из техпроцесса ----------
create or replace function public.app_bom_from_template(p_token uuid, p_template_id uuid, p_order_id uuid, p_product text, p_qty numeric default 1)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ulogin text; ten uuid; bid uuid; tname text; tmat uuid; matname text; munit text; i integer := 0; st record;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select t.name, t.material_id into tname, tmat from public.app_process_templates t
    where t.id = p_template_id and (uid is not null);
  if tname is null then raise exception 'Техпроцесс не найден'; end if;

  insert into public.app_bom (tenant_id, order_id, product, version, qty, source_template_id, created_by, created_login)
  values (ten, p_order_id, coalesce(nullif(trim(p_product),''), tname), '1', greatest(coalesce(p_qty,1),1), p_template_id, uid, ulogin)
  returning app_bom.id into bid;

  if tmat is not null then
    select m.name, m.unit into matname, munit from public.app_materials m where m.id = tmat;
    i := i + 1;
    insert into public.app_bom_lines (bom_id, seq, item_type, material_id, name, qty, unit, norm_hours)
    values (bid, i, 'material', tmat, coalesce(matname, tname), greatest(coalesce(p_qty,1),1), munit, 0);
  end if;

  for st in select st0.operation_id, st0.plan_min, o.name as opname
            from public.app_process_steps st0 left join public.app_operations o on o.id = st0.operation_id
            where st0.template_id = p_template_id order by st0.seq loop
    i := i + 1;
    insert into public.app_bom_lines (bom_id, seq, item_type, operation_id, name, qty, unit, norm_hours)
    values (bid, i, 'operation', st.operation_id, coalesce(st.opname, 'Операция '||i), 0, 'н/ч', round(coalesce(st.plan_min,0)/60.0, 2));
  end loop;

  return query select bid, 'Спецификация создана из техпроцесса';
end $$;

grant execute on function public.app_bom_list(uuid) to anon, authenticated;
grant execute on function public.app_bom_lines_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_bom_save(uuid,uuid,uuid,text,text,jsonb,text,numeric) to anon, authenticated;
grant execute on function public.app_bom_cost(uuid,uuid,numeric) to anon, authenticated;
grant execute on function public.app_bom_from_template(uuid,uuid,uuid,text,numeric) to anon, authenticated;

-- ---------- База знаний: спецификации ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Спецификации','Что такое спецификация (BOM) и как её создать из техпроцесса?',
   'Спецификация — состав изделия: материалы (с количеством) и операции (с нормо-часами). Нажмите «Создать из техпроцесса» и выберите шаблон — материалы и операции подтянутся автоматически из «Справочников». Позиции можно добавить и вручную.',
   'спецификация BOM техпроцесс материалы операции состав'),
  ('Спецификации','Как считается себестоимость по спецификации?',
   'В карточке спецификации показывается расчёт: материалы (кол-во × цена) + работы (нормо-часы × ставка операции) + 15% накладные = итого. Укажите количество изделий — расчёт умножается. Это основа экономики заказа.',
   'себестоимость BOM материалы работы накладные экономика')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and category='Спецификации');
