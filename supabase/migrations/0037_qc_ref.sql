-- ============================================================
-- 3DMP Service · 0037_qc_ref.sql  (v19.0 — переработка «ОТК»)
-- ОТК: количество (всего/годных), связь с нарядом/заявкой, трассируемость.
-- База знаний. Tenant-изоляция. Зависит от 0001..0036.
-- ============================================================

alter table public.app_qc_checks add column if not exists qty_total numeric;
alter table public.app_qc_checks add column if not exists qty_good  numeric;

-- ---------- ОТК: список (расширенный) ----------
drop function if exists public.app_qc_list(uuid);
create or replace function public.app_qc_list(p_token uuid)
returns table (id uuid, number text, product text, status text, inspector text,
               naryad_id uuid, naryad_number text, order_id uuid, order_number text,
               qty_total numeric, qty_good numeric, lines_count bigint, defects_count bigint, open_defects bigint,
               checked_at timestamptz, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select c.id, c.number, c.product, c.status, c.inspector, c.naryad_id, n.number, c.order_id, o.number,
           c.qty_total, c.qty_good,
           (select count(*) from public.app_qc_lines l where l.check_id = c.id),
           (select count(*) from public.app_defects d where d.check_id = c.id),
           (select count(*) from public.app_defects d where d.check_id = c.id and d.status <> 'resolved'),
           c.checked_at, c.created_at
    from public.app_qc_checks c
    left join public.app_naryads n on n.id = c.naryad_id
    left join public.app_orders o on o.id = c.order_id
    where (urole = 'admin' or c.tenant_id = ten)
    order by c.created_at desc;
end $$;

-- ---------- ОТК: создать ----------
drop function if exists public.app_qc_create(uuid,uuid,uuid,text,text);
create or replace function public.app_qc_create(p_token uuid, p_naryad_id uuid, p_order_id uuid, p_product text, p_inspector text,
  p_qty_total numeric default null, p_qty_good numeric default null)
returns table (id uuid, number text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ulogin text; ten uuid; cid uuid; cnum text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  cnum := 'QCK-' || lpad(nextval('public.app_qc_seq')::text, 5, '0');
  insert into public.app_qc_checks (tenant_id, number, naryad_id, order_id, product, inspector, qty_total, qty_good, created_by, created_login)
  values (ten, cnum, p_naryad_id, p_order_id, nullif(trim(p_product),''), nullif(trim(p_inspector),''), p_qty_total, p_qty_good, uid, ulogin)
  returning app_qc_checks.id into cid;
  return query select cid, cnum;
end $$;

-- ---------- ОТК: статус ----------
create or replace function public.app_qc_set_status(p_token uuid, p_check_id uuid, p_status text, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; cnum text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select c.number into cnum from public.app_qc_checks c where c.id = p_check_id and (urole='admin' or c.tenant_id = ten);
  if cnum is null then return query select false,'Чек-лист не найден'; return; end if;
  update public.app_qc_checks set status = p_status, note = nullif(trim(p_note),''), checked_at = now() where id = p_check_id;
  perform public.app_notif_roles_t(ten, array['admin','manager','owner','chief','master','qc'],
    case when p_status='passed' then 'ОТК: годен ' || cnum when p_status='failed' then 'ОТК: брак по ' || cnum else 'ОТК ' || cnum end,
    coalesce(nullif(trim(p_note),''),''), 'apps/qc/index.html');
  return query select true, case when p_status = 'passed' then 'Принято' when p_status='failed' then 'Зафиксирован брак' else 'Сохранено' end;
end $$;

-- ---------- Трассируемость по чек-листу ----------
create or replace function public.app_qc_trace(p_token uuid, p_check_id uuid)
returns table (kind text, title text, detail text, ts timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; c record;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select c0.* into c from public.app_qc_checks c0 where c0.id = p_check_id and (urole='admin' or c0.tenant_id = ten);
  if c.id is null then raise exception 'Чек-лист не найден'; end if;

  return query
  -- заявка
  select 'Заявка'::text as kind, o.number as title, o.title as detail, o.created_at as ts
    from public.app_orders o where o.id = c.order_id
  union all
  -- наряд
  select 'Наряд'::text, n.number, n.title, n.created_at
    from public.app_naryads n where n.id = c.naryad_id
  union all
  -- операции наряда
  select 'Операция'::text, op.seq || '. ' || op.operation,
         'план ' || coalesce(op.plan_hours,0) || ' ч · факт ' || coalesce(op.fact_hours,0) || ' ч' || case when op.done then ' · выполнено' else '' end,
         n.created_at
    from public.app_naryad_ops op join public.app_naryads n on n.id = op.naryad_id
    where op.naryad_id = c.naryad_id
  union all
  -- расход материалов по заявке
  select 'Материал'::text, coalesce(m.name,'—'),
         case when v.kind='out' then 'расход ' else 'приход ' end || coalesce(v.qty,0) || ' ' || coalesce(m.unit,''),
         v.created_at
    from public.app_stock_moves v left join public.app_materials m on m.id = v.material_id
    where v.order_id = c.order_id
  union all
  -- дефекты чек-листа
  select 'Дефект'::text, d.title,
         d.severity || ' · ' || case when d.status='resolved' then 'закрыт' else 'открыт' end,
         d.created_at
    from public.app_defects d where d.check_id = c.id
  order by ts;
end $$;

grant execute on function public.app_qc_list(uuid) to anon, authenticated;
grant execute on function public.app_qc_create(uuid,uuid,uuid,text,text,numeric,numeric) to anon, authenticated;
grant execute on function public.app_qc_set_status(uuid,uuid,text,text) to anon, authenticated;
grant execute on function public.app_qc_trace(uuid,uuid) to anon, authenticated;

-- ---------- База знаний: ОТК ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('ОТК','Как провести контроль (чек-лист)?',
   'В «ОТК» создайте чек-лист: наряд, изделие, контролёр, количество (всего/годных). Добавьте позиции (параметр/норма/факт/результат) и дефекты. Итог: «Годен» или «Брак». При браке и критических дефектах приходят уведомления.',
   'ОТК чек-лист контроль дефект годен брак'),
  ('ОТК','Что такое трассируемость изделия?',
   'В карточке чек-листа блок «Трассируемость» собирает всю цепочку: заявка → наряд → операции наряда → расход материалов → дефекты. Это основа СМК и паспорта изделия: видно, из чего и как сделано изделие и какие были замечания.',
   'трассируемость СМК паспорт материалы операции дефекты')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and category='ОТК');
