-- ============================================================
-- 3DMP Service · 0131_global_search.sql  (S9 — системный поиск и база знаний)
-- app_global_search (сквозной поиск: БЗ, заявки, оборудование, заказчики)
-- и app_knowledge_search (поиск по базе знаний). Идемпотентно. Зависит от 0001..0130.
-- ============================================================

-- ---------- Поиск по базе знаний ----------
drop function if exists public.app_knowledge_search(uuid,text,integer);
create or replace function public.app_knowledge_search(p_token uuid, p_q text, p_limit integer default 30)
returns table (id uuid, category text, question text, answer text, tags text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole is null then raise exception 'Доступ запрещён'; end if;
  if urole not in ('admin','owner','manager','director','chief','master','technologist','qc','supply','support','operator','economist') then
    raise exception 'Нет доступа';
  end if;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select k.id, k.category, k.question, k.answer, k.tags
      from public.app_knowledge k
     where (urole='admin' or k.tenant_id = ten or k.tenant_id is null)
       and (qq='' or lower(coalesce(k.question,'')) like '%'||qq||'%'
            or lower(coalesce(k.answer,'')) like '%'||qq||'%'
            or lower(coalesce(k.category,'')) like '%'||qq||'%'
            or lower(coalesce(k.tags,'')) like '%'||qq||'%')
     order by (lower(coalesce(k.question,'')) like '%'||qq||'%') desc, k.category, k.question
     limit greatest(1, least(coalesce(p_limit,30),100));
end $$;

-- ---------- Сквозной поиск по системе ----------
drop function if exists public.app_global_search(uuid,text,integer);
create or replace function public.app_global_search(p_token uuid, p_q text, p_limit integer default 12)
returns table (kind text, title text, subtitle text, url text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text; lim int;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),'')); lim := greatest(1, least(coalesce(p_limit,12),50));
  if qq = '' then return; end if;
  return query
  (
    select 'kb'::text, k.question, coalesce(k.category,'База знаний'), 'apps/guide/index.html'
      from public.app_knowledge k
     where (urole='admin' or k.tenant_id = ten or k.tenant_id is null)
       and (lower(coalesce(k.question,'')) like '%'||qq||'%' or lower(coalesce(k.answer,'')) like '%'||qq||'%' or lower(coalesce(k.tags,'')) like '%'||qq||'%')
  )
  union all
  (
    select 'request'::text, r.number || ' · ' || coalesce(r.title,''), coalesce(c.name,'заявка сервиса'), 'apps/service/index.html'
      from public.app_service_requests r left join public.app_customers c on c.id = r.customer_id
     where (urole='admin' or r.tenant_id = ten)
       and (lower(coalesce(r.number,'')) like '%'||qq||'%' or lower(coalesce(r.title,'')) like '%'||qq||'%')
  )
  union all
  (
    select 'equipment'::text, e.name, 'станок ' || coalesce(e.code,''), 'apps/service/index.html'
      from public.app_equipment e
     where (urole='admin' or e.tenant_id = ten)
       and (lower(coalesce(e.name,'')) like '%'||qq||'%' or lower(coalesce(e.code,'')) like '%'||qq||'%')
  )
  union all
  (
    select 'customer'::text, c.name, 'заказчик ' || coalesce(c.inn,''), 'apps/client/index.html'
      from public.app_customers c
     where (urole='admin' or c.tenant_id = ten)
       and lower(coalesce(c.name,'')) like '%'||qq||'%'
  )
  union all
  (
    select 'order'::text, o.number || ' · ' || coalesce(o.title,''), 'заказ', 'apps/orders/index.html'
      from public.app_orders o
     where (urole='admin' or o.tenant_id = ten)
       and (lower(coalesce(o.number,'')) like '%'||qq||'%' or lower(coalesce(o.title,'')) like '%'||qq||'%')
  )
  limit lim;
end $$;

grant execute on function public.app_knowledge_search(uuid,text,integer) to anon, authenticated;
grant execute on function public.app_global_search(uuid,text,integer)     to anon, authenticated;
