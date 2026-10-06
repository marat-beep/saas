-- ============================================================
-- 3DMP Service · 0109_econ_org.sql  (v94 — PLAN_MODERNIZATION, Партия F)
-- Экономика/Персонал:
--   * нормы → себестоимость → КП: КП из маршрута (работы+материалы+накладные, наценка);
--   * оргструктура ↔ роли: покрытие подразделений по ролям/логинам (app_employees).
-- Идемпотентно. Зависит от 0001..0108.
-- ============================================================

-- ---------- КП из маршрута (нормы→себестоимость→КП) ----------
create or replace function public.app_quote_from_route(p_token uuid, p_route_id uuid, p_margin_pct numeric default 0, p_valid_days integer default 30)
returns table (id uuid, number text, amount numeric, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; urole text; ten uuid; r record; margin numeric; base numeric; amt numeric; vd date;
        sid uuid; did uuid; dnum text; cust text; cust_id uuid; ord_num text; body text; st record; cnt int := 0;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin, s.urole into uid, ulogin, urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select r0.* into r from public.app_routes r0 where r0.id = p_route_id and (urole='admin' or r0.tenant_id=ten);
  if r.id is null then raise exception 'Маршрут не найден'; return; end if;
  margin := greatest(coalesce(p_margin_pct,0),0);
  base := coalesce(r.total_cost, coalesce(r.work_cost,0) + coalesce(r.material_cost,0) + coalesce(r.overhead,0));
  amt := round(coalesce(base,0) * (1 + margin/100.0), 2);
  vd := current_date + greatest(coalesce(p_valid_days,30),1);
  if r.order_id is not null then
    select o.customer_id, o.number into cust_id, ord_num from public.app_orders o where o.id = r.order_id;
    if cust_id is not null then select c.name into cust from public.app_customers c where c.id = cust_id; end if;
  end if;
  body := 'Коммерческое предложение по маршруту ' || coalesce(r.number,'') || ' от ' || to_char(current_date,'DD.MM.YYYY') || E'\n' ||
          coalesce(r.name,'') || E'\n\nШаги:' || E'\n';
  for st in
    select s2.seq, coalesce(o.name,'') as opname, s2.plan_min, s2.cost
      from public.app_route_steps s2 left join public.app_operations o on o.id = s2.operation_id
      where s2.route_id = p_route_id order by s2.seq
  loop
    cnt := cnt + 1;
    body := body || '  ' || st.seq::text || '. ' || st.opname || '  ·  ' || coalesce(st.plan_min,0)::text || ' мин  ·  ' ||
            round(coalesce(st.cost,0),2)::text || ' ₽' || E'\n';
  end loop;
  body := body || E'\n' || 'Материалы: ' || round(coalesce(r.material_cost,0),2)::text || ' ₽' || E'\n' ||
          'Работы: ' || round(coalesce(r.work_cost,0),2)::text || ' ₽' || E'\n' ||
          'Накладные: ' || round(coalesce(r.overhead,0),2)::text || ' ₽' || E'\n' ||
          'Наценка: ' || margin::text || ' %' || E'\n' || 'ИТОГО: ' || amt::text || ' ₽';
  select sc.id into sid from public.app_schemas sc where sc.code='kp' and (urole='admin' or sc.tenant_id=ten) order by (sc.tenant_id=ten) desc limit 1;
  dnum := 'KP-' || lpad(nextval('public.app_doc_seq')::text, 5, '0');
  insert into public.app_documents (tenant_id, doc_type, number, title, order_id, customer_id, amount, valid_until, status, content, fields, schema_id, created_by, created_login)
  values (ten, 'kp', dnum, 'КП из маршрута ' || coalesce(r.number,''), r.order_id, cust_id, amt, vd, 'draft', body,
          jsonb_build_object('customer', coalesce(cust,''), 'valid_until', to_char(vd,'DD.MM.YYYY'), 'discount', margin, 'items', 'из маршрута'),
          sid, uid, ulogin)
  returning app_documents.id into did;
  insert into public.app_document_versions (document_id, version, title, content, by_login)
  values (did, 1, 'КП из маршрута ' || coalesce(r.number,''), body, ulogin);
  return query select did, dnum, amt, 'КП из маршрута создано';
end $$;

-- ---------- Оргструктура ↔ роли ----------
create or replace function public.app_org_role_coverage(p_token uuid)
returns table (dept text, employees bigint, roles text, logins text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select coalesce(nullif(trim(e.dept),''),'—') as dept,
           count(*)::bigint,
           coalesce(string_agg(distinct nullif(trim(e.role),''), ', '), '') as roles,
           coalesce(string_agg(distinct nullif(trim(e.user_login),''), ', '), '') as logins
    from public.app_employees e
    where (urole='admin' or e.tenant_id=ten) and coalesce(e.active,true)
    group by 1
    order by 1;
end $$;

grant execute on function public.app_quote_from_route(uuid,uuid,numeric,integer) to anon, authenticated;
grant execute on function public.app_org_role_coverage(uuid) to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Экономика','Нормы → себестоимость → КП и оргструктура ↔ роли (Партия F)',
   'Нормы→себестоимость→КП: app_quote_from_route формирует КП из маршрута (материалы+работы+накладные, наценка, срок действия); маршрут, в свою очередь, считается по нормам операций (app_route_calc/app_norm_calc). Оргструктура↔роли: app_org_role_coverage показывает по подразделениям число сотрудников, роли и логины (app_employees) — контроль покрытия ролей по оргструктуре.',
   'экономика нормы себестоимость КП маршрут оргструктура роли покрытие партия F app_quote_from_route app_org_role_coverage')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Нормы → себестоимость → КП и оргструктура ↔ роли (Партия F)');
