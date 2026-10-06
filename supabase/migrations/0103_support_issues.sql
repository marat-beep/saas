-- ============================================================
-- 3DMP Service · 0103_support_issues.sql  (v85 — эскалация тикета ↔ проблемы)
-- Связка Support Desk с модулем «Проблемы и эскалация» (app_issues):
--   * колонка app_support_tickets.issue_id;
--   * помощник app_support_ticket_link_issue (создать/связать проблему);
--   * эскалация тикета (ручная и сканером SLA) создаёт проблему;
--   * смена статуса тикета синхронизирует статус проблемы;
--   * карточка тикета отдаёт связанную проблему.
-- Идемпотентно. Зависит от 0001..0102.
-- ============================================================

alter table public.app_support_tickets
  add column if not exists issue_id uuid references public.app_issues (id) on delete set null;

-- ---------- Помощник: создать/связать проблему ----------
create or replace function public.app_support_ticket_link_issue(p_tenant uuid, p_ticket_id uuid, p_login text)
returns uuid
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare xid uuid; tnum text; tsub text; tdesc text;
begin
  select t.issue_id, t.number, t.subject, t.description into xid, tnum, tsub, tdesc
    from public.app_support_tickets t where t.id = p_ticket_id;
  if not found then return null; end if;
  if xid is not null then return xid; end if;
  insert into public.app_issues (tenant_id, title, description, priority, source, status, created_login, escalated, escalated_at)
  values (p_tenant,
          'Тикет ' || coalesce(tnum, '') || ': ' || coalesce(tsub, ''),
          nullif(trim(coalesce(tdesc, '') || case when tnum is not null then E'\nИсточник: Support Desk ' || tnum else '' end), ''),
          'critical', 'support', 'open', p_login, true, now())
  returning id into xid;
  update public.app_support_tickets set issue_id = xid, updated_at = now() where id = p_ticket_id;
  return xid;
end $$;
revoke all on function public.app_support_ticket_link_issue(uuid, uuid, text) from public, anon, authenticated;

-- ---------- Карточка (+ связанная проблема) ----------
drop function if exists public.app_support_ticket_get(uuid, uuid);
create or replace function public.app_support_ticket_get(p_token uuid, p_id uuid)
returns table (id uuid, number text, subject text, description text, category text, priority text, status text, scope text,
               requester_login text, requester_name text, requester_role text, assignee_login text, module text, url text,
               sla_response_due timestamptz, sla_resolve_due timestamptz, first_response_at timestamptz, escalated boolean, csat int, csat_comment text, created_at timestamptz,
               issue_id uuid, issue_title text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; ulogin text; agent boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  agent := urole in ('admin','owner','manager','director','support');
  return query
    select t.id, t.number, t.subject, t.description, t.category, t.priority, t.status, t.scope,
           t.requester_login, t.requester_name, t.requester_role, t.assignee_login, t.module, t.url,
           t.sla_response_due, t.sla_resolve_due, t.first_response_at, t.escalated, t.csat, t.csat_comment, t.created_at,
           t.issue_id, i.title
    from public.app_support_tickets t
    left join public.app_issues i on i.id = t.issue_id
    where t.id=p_id and (urole='admin' or (agent and t.tenant_id=ten) or t.requester_login=ulogin);
end $$;
grant execute on function public.app_support_ticket_get(uuid,uuid) to anon, authenticated;

-- ---------- Эскалация: создать проблему ----------
create or replace function public.app_support_ticket_escalate(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; tnum text; xid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','support') then return query select false,'Недостаточно прав'; return; end if;
  select number into tnum from public.app_support_tickets where id=p_id and (urole='admin' or tenant_id=ten);
  update public.app_support_tickets set escalated=true, escalated_at=now(), scope='platform', status=case when status in ('new','open') then 'in_progress' else status end, updated_at=now()
   where id=p_id and (urole='admin' or tenant_id=ten);
  if not found then return query select false,'Тикет не найден'; return; end if;
  xid := public.app_support_ticket_link_issue(ten, p_id, ulogin);
  if ten is not null then perform public.app_notif_roles_t(ten, array['admin','owner'], 'Эскалация тикета '||coalesce(tnum,''), 'Создана проблема в реестре «Проблемы»', 'apps/support/index.html'); end if;
  return query select true, case when xid is not null then 'Тикет эскалирован, создана проблема' else 'Тикет эскалирован' end;
end $$;

-- ---------- Сканер SLA: создаёт проблемы для эскалированных ----------
create or replace function public.app_support_escalate_scan(p_token uuid)
returns table (escalated int)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; n int := 0; rec record; ulogin text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','support') then raise exception 'Недостаточно прав'; end if;
  update public.app_support_tickets t set escalated=true, escalated_at=now(), updated_at=now()
   where (urole='admin' or t.tenant_id=ten) and coalesce(t.escalated,false)=false
     and t.status not in ('resolved','closed')
     and ((t.first_response_at is null and t.sla_response_due < now()) or (t.sla_resolve_due < now()));
  get diagnostics n = row_count;
  -- связать с проблемами все эскалированные тикеты без связи
  for rec in
    select t.id from public.app_support_tickets t
    where (urole='admin' or t.tenant_id=ten) and coalesce(t.escalated,false) and t.issue_id is null
      and t.status not in ('resolved','closed')
  loop
    perform public.app_support_ticket_link_issue(ten, rec.id, ulogin);
  end loop;
  if n>0 and ten is not null then perform public.app_notif_roles_t(ten, array['admin','owner','manager','support'], 'Просрочено тикетов: '||n, 'Нарушен SLA, созданы проблемы', 'apps/support/index.html'); end if;
  return query select n;
end $$;

-- ---------- Смена статуса: синхронизировать проблему ----------
create or replace function public.app_support_ticket_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; agent boolean; iss uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); agent := urole in ('admin','owner','manager','director','support');
  if p_status not in ('new','open','in_progress','waiting','resolved','closed') then return query select false,'Неверный статус'; return; end if;
  select t.issue_id into iss from public.app_support_tickets t
   where t.id=p_id and (urole='admin' or (agent and t.tenant_id=ten));
  update public.app_support_tickets set status=p_status,
    resolved_at = case when p_status='resolved' then now() else resolved_at end,
    closed_at = case when p_status='closed' then now() else closed_at end, updated_at=now()
   where id=p_id and (urole='admin' or (agent and tenant_id=ten));
  if iss is not null and p_status in ('resolved','closed') then
    update public.app_issues set status=p_status, updated_at=now() where id=iss;
  end if;
  return query select true,'Статус обновлён';
end $$;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Поддержка','Связь тикета с проблемой (эскалация)',
   'При эскалации тикета (вручную или сканером SLA) автоматически создаётся запись в реестре «Проблемы и эскалация» (app_issues, источник support, приоритет критический) и связывается с тикетом (issue_id). При переводе тикета в «Решён»/«Закрыт» статус связанной проблемы синхронизируется. Карточка тикета показывает связанную проблему.',
   'поддержка эскалация тикет проблема app_issues связь issue_id SLA')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Связь тикета с проблемой (эскалация)');
