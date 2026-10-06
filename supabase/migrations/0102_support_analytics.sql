-- ============================================================
-- 3DMP Service · 0102_support_analytics.sql  (v84 — аналитика поддержки)
-- Срезы тикетов: по статусу, категории, модулю. Зависит от 0001..0101.
-- ============================================================

create or replace function public.app_support_analytics(p_token uuid)
returns table (kind text, name text, cnt bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; agent boolean; ulogin text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); agent := urole in ('admin','owner','manager','director','support');
  return query
    select 'status'::text, t.status, count(*)::bigint from public.app_support_tickets t
      where (urole='admin' or (agent and t.tenant_id=ten) or t.requester_login=ulogin)
      group by t.status
    union all
    select 'category'::text, coalesce(t.category,'—'), count(*)::bigint from public.app_support_tickets t
      where (urole='admin' or (agent and t.tenant_id=ten) or t.requester_login=ulogin)
      group by t.category
    union all
    select 'module'::text, coalesce(nullif(t.module,''),'—'), count(*)::bigint from public.app_support_tickets t
      where (urole='admin' or (agent and t.tenant_id=ten) or t.requester_login=ulogin)
      group by nullif(t.module,'')
    union all
    select 'scope'::text, t.scope, count(*)::bigint from public.app_support_tickets t
      where (urole='admin' or (agent and t.tenant_id=ten) or t.requester_login=ulogin)
      group by t.scope
    order by 1, 3 desc;
end $$;

grant execute on function public.app_support_analytics(uuid) to anon, authenticated;

insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Поддержка','Аналитика поддержки',
   'Срезы тикетов по статусу, категории, модулю и уровню (scope) для роли support/admin. Вложения тикета хранятся в app_files (entity_type=support_ticket), включая скриншоты из модуля замечаний.',
   'аналитика поддержки тикеты статус категория модуль вложения app_files')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Аналитика поддержки');
