-- ============================================================
-- 3DMP Service · 0100_support.sql  (v80 — модуль «Тикеты поддержки»)
-- app_support_tickets / _messages / _sla / _kb + RPC. Роль 'support'.
-- Tenant-изоляция, внутренние заметки скрыты от заявителя. Зависит 0001..0099.
-- ============================================================

create sequence if not exists public.app_support_seq;

create table if not exists public.app_support_tickets (
  id uuid primary key default gen_random_uuid(), tenant_id uuid references public.tenants (id),
  number text, subject text not null, description text,
  category text default 'Другое', priority text default 'normal', status text default 'new',
  scope text default 'internal', channel text default 'web',
  requester_login text, requester_name text, requester_role text,
  module text, url text, related_type text, related_id uuid, assignee_login text,
  sla_response_due timestamptz, sla_resolve_due timestamptz, first_response_at timestamptz, resolved_at timestamptz, closed_at timestamptz,
  escalated boolean default false, escalated_at timestamptz, csat int, csat_comment text,
  created_login text, created_at timestamptz default now(), updated_at timestamptz default now()
);
create index if not exists app_support_tickets_idx on public.app_support_tickets (tenant_id, status, created_at desc);
alter table public.app_support_tickets enable row level security;

create table if not exists public.app_support_messages (
  id uuid primary key default gen_random_uuid(), ticket_id uuid references public.app_support_tickets (id) on delete cascade,
  author_login text, author_name text, author_role text, body text, is_internal boolean default false, created_at timestamptz default now()
);
create index if not exists app_support_messages_idx on public.app_support_messages (ticket_id, created_at);
alter table public.app_support_messages enable row level security;

create table if not exists public.app_support_sla (
  id uuid primary key default gen_random_uuid(), tenant_id uuid references public.tenants (id), priority text, response_minutes int, resolve_minutes int
);
alter table public.app_support_sla enable row level security;

create table if not exists public.app_support_kb (
  id uuid primary key default gen_random_uuid(), tenant_id uuid references public.tenants (id),
  title text not null, body text, tags text, published boolean default false, created_at timestamptz default now()
);
alter table public.app_support_kb enable row level security;

-- ---------- SLA ----------
create or replace function public.app_support_sla_due(p_priority text)
returns table (response_minutes int, resolve_minutes int)
language plpgsql security definer set search_path = public
as $$
declare pr text;
begin
  pr := lower(coalesce(nullif(trim(p_priority),''),'normal'));
  return query select
    case pr when 'critical' then 30 when 'high' then 120 when 'low' then 480 else 240 end,
    case pr when 'critical' then 240 when 'high' then 1440 when 'low' then 7200 else 2880 end;
end $$;

-- ---------- Список ----------
create or replace function public.app_support_ticket_list(p_token uuid, p_status text default null, p_scope text default null, p_mine boolean default false)
returns table (id uuid, number text, subject text, category text, priority text, status text, scope text, requester_name text, assignee_login text, sla_resolve_due timestamptz, escalated boolean, updated_at timestamptz)
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
    select t.id, t.number, t.subject, t.category, t.priority, t.status, t.scope, t.requester_name, t.assignee_login, t.sla_resolve_due, t.escalated, t.updated_at
    from public.app_support_tickets t
    where (urole='admin' or (agent and t.tenant_id=ten) or t.requester_login=ulogin)
      and (coalesce(p_status,'')='' or t.status=p_status)
      and (coalesce(p_scope,'')='' or t.scope=p_scope)
      and (not coalesce(p_mine,false) or t.requester_login=ulogin or t.assignee_login=ulogin)
    order by (t.status in ('resolved','closed')), t.updated_at desc;
end $$;

-- ---------- Карточка ----------
create or replace function public.app_support_ticket_get(p_token uuid, p_id uuid)
returns table (id uuid, number text, subject text, description text, category text, priority text, status text, scope text,
               requester_login text, requester_name text, requester_role text, assignee_login text, module text, url text,
               sla_response_due timestamptz, sla_resolve_due timestamptz, first_response_at timestamptz, escalated boolean, csat int, csat_comment text, created_at timestamptz)
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
           t.sla_response_due, t.sla_resolve_due, t.first_response_at, t.escalated, t.csat, t.csat_comment, t.created_at
    from public.app_support_tickets t
    where t.id=p_id and (urole='admin' or (agent and t.tenant_id=ten) or t.requester_login=ulogin);
end $$;

create or replace function public.app_support_message_list(p_token uuid, p_ticket_id uuid)
returns table (id uuid, author_login text, author_name text, author_role text, body text, is_internal boolean, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; ulogin text; agent boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  agent := urole in ('admin','owner','manager','director','support');
  if not exists (select 1 from public.app_support_tickets t where t.id=p_ticket_id and (urole='admin' or (agent and t.tenant_id=ten) or t.requester_login=ulogin)) then raise exception 'Тикет не найден'; end if;
  return query
    select m.id, m.author_login, m.author_name, m.author_role, m.body, m.is_internal, m.created_at
    from public.app_support_messages m
    where m.ticket_id=p_ticket_id and (agent or not m.is_internal)  -- заявителю внутренние заметки не видны
    order by m.created_at;
end $$;

-- ---------- Создание ----------
create or replace function public.app_support_ticket_create(p_token uuid, p_subject text, p_description text, p_category text, p_priority text,
  p_scope text, p_module text, p_url text, p_related_type text, p_related_id uuid)
returns table (id uuid, number text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; ulogin text; uname text; urole text; tid uuid; tnum text; rmin int; smin int;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.ulogin, s.urole into ulogin, urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_subject),'')='' then raise exception 'Укажите тему'; end if;
  select response_minutes, resolve_minutes into rmin, smin from public.app_support_sla_due(p_priority);
  tnum := 'SUP-' || lpad(nextval('public.app_support_seq')::text, 5, '0');
  insert into public.app_support_tickets (tenant_id, number, subject, description, category, priority, status, scope, requester_login, requester_role, module, url, related_type, related_id, sla_response_due, sla_resolve_due, created_login)
  values (ten, tnum, trim(p_subject), nullif(trim(p_description),''), coalesce(nullif(trim(p_category),''),'Другое'), coalesce(nullif(trim(p_priority),''),'normal'),
          'new', coalesce(nullif(trim(p_scope),''),'internal'), ulogin, urole, nullif(trim(p_module),''), nullif(trim(p_url),''),
          nullif(trim(p_related_type),''), p_related_id, now() + make_interval(mins => rmin), now() + make_interval(mins => smin), ulogin)
  returning id into tid;
  if ten is not null then perform public.app_notif_roles_t(ten, array['admin','owner','manager','support'], 'Новый тикет '||tnum||': '||trim(p_subject), coalesce(p_url,''), 'apps/support/index.html'); end if;
  return query select tid, tnum;
end $$;

-- ---------- Ответ ----------
create or replace function public.app_support_ticket_reply(p_token uuid, p_id uuid, p_body text, p_internal boolean default false)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ulogin text; urole text; ten uuid; agent boolean; lname text; treq text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.ulogin, s.urole into ulogin, urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  agent := urole in ('admin','owner','manager','director','support');
  if coalesce(trim(p_body),'')='' then return query select false,'Пустое сообщение'; return; end if;
  select nullif(trim(coalesce(requester_name,'')),''), requester_login into lname, treq from public.app_support_tickets t where t.id=p_id and (urole='admin' or (agent and t.tenant_id=ten) or t.requester_login=ulogin);
  if not found then return query select false,'Тикет не найден'; return; end if;
  insert into public.app_support_messages (ticket_id, author_login, author_name, author_role, body, is_internal)
  values (p_id, ulogin, coalesce(lname, ulogin), urole, trim(p_body), coalesce(p_internal,false));
  update public.app_support_tickets set first_response_at = coalesce(first_response_at, case when agent and not coalesce(p_internal,false) then now() end),
    status = case when status='new' and agent and not coalesce(p_internal,false) then 'open' else status end, updated_at=now()
   where id=p_id;
  if treq is not null and agent and not coalesce(p_internal,false) then
    perform public.app_notif_roles_t(ten, array['admin','owner','manager','support'], 'Ответ по тикету', coalesce(trim(p_body),''), 'apps/support/index.html');
  end if;
  return query select true,'Ответ сохранён';
end $$;

-- ---------- Статус/назначение/эскалация/CSAT/удаление ----------
create or replace function public.app_support_ticket_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; agent boolean;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); agent := urole in ('admin','owner','manager','director','support');
  if p_status not in ('new','open','in_progress','waiting','resolved','closed') then return query select false,'Неверный статус'; return; end if;
  update public.app_support_tickets set status=p_status,
    resolved_at = case when p_status='resolved' then now() else resolved_at end,
    closed_at = case when p_status='closed' then now() else closed_at end, updated_at=now()
   where id=p_id and (urole='admin' or (agent and tenant_id=ten));
  return query select true,'Статус обновлён';
end $$;

create or replace function public.app_support_ticket_assign(p_token uuid, p_id uuid, p_assignee_login text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','support') then return query select false,'Недостаточно прав'; return; end if;
  update public.app_support_tickets set assignee_login=nullif(trim(p_assignee_login),''), status=case when status='new' then 'open' else status end, updated_at=now()
   where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Исполнитель назначен';
end $$;

create or replace function public.app_support_ticket_escalate(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; tnum text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','support') then return query select false,'Недостаточно прав'; return; end if;
  select number into tnum from public.app_support_tickets where id=p_id and (urole='admin' or tenant_id=ten);
  update public.app_support_tickets set escalated=true, escalated_at=now(), scope='platform', status=case when status in ('new','open') then 'in_progress' else status end, updated_at=now()
   where id=p_id and (urole='admin' or tenant_id=ten);
  if ten is not null then perform public.app_notif_roles_t(ten, array['admin','owner'], 'Эскалация тикета '||coalesce(tnum,''), 'Тикет эскалирован на платформу', 'apps/support/index.html'); end if;
  return query select true,'Тикет эскалирован';
end $$;

create or replace function public.app_support_ticket_csat(p_token uuid, p_id uuid, p_score int, p_comment text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ulogin text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.ulogin into ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  update public.app_support_tickets set csat=greatest(1,least(5,coalesce(p_score,5))), csat_comment=nullif(trim(p_comment),''), updated_at=now()
   where id=p_id and requester_login=ulogin;
  return query select true,'Спасибо за оценку';
end $$;

create or replace function public.app_support_ticket_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole <> 'admin' then return query select false,'Только администратор'; return; end if;
  delete from public.app_support_tickets where id=p_id;
  return query select true,'Тикет удалён';
end $$;

create or replace function public.app_support_escalate_scan(p_token uuid)
returns table (escalated int)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; n int := 0;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','support') then raise exception 'Недостаточно прав'; end if;
  update public.app_support_tickets t set escalated=true, escalated_at=now(), updated_at=now()
   where (urole='admin' or t.tenant_id=ten) and coalesce(t.escalated,false)=false
     and t.status not in ('resolved','closed')
     and ((t.first_response_at is null and t.sla_response_due < now()) or (t.sla_resolve_due < now()));
  get diagnostics n = row_count;
  if n>0 and ten is not null then perform public.app_notif_roles_t(ten, array['admin','owner','manager','support'], 'Просрочено тикетов: '||n, 'Нарушен SLA', 'apps/support/index.html'); end if;
  return query select n;
end $$;

create or replace function public.app_support_kpi(p_token uuid)
returns table (total bigint, new_cnt bigint, in_work bigint, overdue bigint, resolved30 bigint, avg_first_min numeric, csat_avg numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; agent boolean; ulogin text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); agent := urole in ('admin','owner','manager','director','support');
  return query select
    count(*), count(*) filter (where status='new'),
    count(*) filter (where status in ('open','in_progress','waiting')),
    count(*) filter (where coalesce(escalated,false) and status not in ('resolved','closed')),
    count(*) filter (where status in ('resolved','closed') and resolved_at >= now() - interval '30 days'),
    round(avg(extract(epoch from (first_response_at - created_at))/60) filter (where first_response_at is not null),1),
    round(avg(csat) filter (where csat is not null),1)
    from public.app_support_tickets t
    where (urole='admin' or (agent and t.tenant_id=ten) or t.requester_login=ulogin);
end $$;

-- ---------- База знаний ----------
create or replace function public.app_support_kb_list(p_token uuid, p_query text default null)
returns table (id uuid, title text, body text, tags text, published boolean, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text; agent boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_query),'')); agent := urole in ('admin','owner','manager','director','support');
  return query select k.id, k.title, k.body, k.tags, k.published, k.created_at
    from public.app_support_kb k
    where (k.tenant_id is null or urole='admin' or k.tenant_id=ten)
      and (agent or k.published)
      and (qq='' or lower(k.title) like '%'||qq||'%' or lower(coalesce(k.tags,'')) like '%'||qq||'%' or lower(coalesce(k.body,'')) like '%'||qq||'%')
    order by k.published desc, k.created_at desc;
end $$;

create or replace function public.app_support_kb_save(p_token uuid, p_id uuid, p_title text, p_body text, p_tags text, p_published boolean)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','support') then return query select false,'Недостаточно прав'; return; end if;
  if coalesce(trim(p_title),'')='' then return query select false,'Укажите заголовок'; return; end if;
  if p_id is null then
    insert into public.app_support_kb (tenant_id, title, body, tags, published) values (ten, trim(p_title), nullif(trim(p_body),''), nullif(trim(p_tags),''), coalesce(p_published,false));
    return query select true,'Статья создана';
  else
    update public.app_support_kb set title=trim(p_title), body=nullif(trim(p_body),''), tags=nullif(trim(p_tags),''), published=coalesce(p_published,published)
     where id=p_id and (urole='admin' or tenant_id=ten);
    return query select true,'Статья обновлена';
  end if;
end $$;

grant execute on function public.app_support_sla_due(text) to anon, authenticated;
grant execute on function public.app_support_ticket_list(uuid,text,text,boolean) to anon, authenticated;
grant execute on function public.app_support_ticket_get(uuid,uuid) to anon, authenticated;
grant execute on function public.app_support_message_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_support_ticket_create(uuid,text,text,text,text,text,text,text,text,uuid) to anon, authenticated;
grant execute on function public.app_support_ticket_reply(uuid,uuid,text,boolean) to anon, authenticated;
grant execute on function public.app_support_ticket_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_support_ticket_assign(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_support_ticket_escalate(uuid,uuid) to anon, authenticated;
grant execute on function public.app_support_ticket_csat(uuid,uuid,int,text) to anon, authenticated;
grant execute on function public.app_support_ticket_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_support_escalate_scan(uuid) to anon, authenticated;
grant execute on function public.app_support_kpi(uuid) to anon, authenticated;
grant execute on function public.app_support_kb_list(uuid,text) to anon, authenticated;
grant execute on function public.app_support_kb_save(uuid,uuid,text,text,text,boolean) to anon, authenticated;

-- ---------- Демо (тенант A) ----------
do $$
declare A constant uuid := 'aaaaaaaa-0000-0000-0000-000000000001'; tid uuid; rmin int; smin int;
begin
  if not exists (select 1 from public.app_support_tickets where tenant_id=A) then
    select response_minutes, resolve_minutes into rmin, smin from public.app_support_sla_due('high');
    insert into public.app_support_tickets (tenant_id, number, subject, description, category, priority, status, scope, requester_login, requester_name, requester_role, sla_response_due, sla_resolve_due, created_login)
    values (A, 'SUP-'||lpad(nextval('public.app_support_seq')::text,5,'0'), 'Не открывается отчёт по нарядам', 'При выборе периода пустой список.', 'Техсбой', 'high', 'open', 'internal', 'manager', 'Менеджер', 'manager', now()+make_interval(mins=>rmin), now()+make_interval(mins=>smin), 'manager')
    returning id into tid;
    insert into public.app_support_messages (ticket_id, author_login, author_name, author_role, body, is_internal) values
      (tid, 'manager', 'Менеджер', 'manager', 'Добрый день, отчёт пустой за прошлый месяц.', false),
      (tid, 'support', 'Поддержка', 'support', 'Проверяю фильтры дат.', false);
    insert into public.app_support_tickets (tenant_id, number, subject, description, category, priority, status, scope, requester_login, requester_name, requester_role, created_login)
    values (A, 'SUP-'||lpad(nextval('public.app_support_seq')::text,5,'0'), 'Заявка: добавить колонку «Исполнитель» в список', 'Хотим видеть исполнителя в списке нарядов.', 'Доработка', 'normal', 'waiting', 'internal', 'technologist', 'Технолог', 'technologist', 'technologist');
  end if;
  if not exists (select 1 from public.app_support_kb where tenant_id=A) then
    insert into public.app_support_kb (tenant_id, title, body, tags, published) values
      (A, 'Как создать заявку', 'Откройте «Заявки» → «Новая заявка» и заполните поля.', 'заявки,начало', true),
      (A, 'Почему пустой отчёт', 'Проверьте период и фильтр по рабочему центру.', 'отчёты,фильтры', true);
  end if;
end $$;

insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Поддержка','Тикеты поддержки (Support Desk)',
   'Модуль поддержки: тикеты (SUP-NNNNN) с категорией/приоритетом/scope (1-й/2-й уровень), перепиской и внутренними заметками (скрыты от заявителя), SLA и эскалацией, назначением исполнителя, CSAT, базой знаний. Заявитель видит свои тикеты; роль support/owner/manager — тикеты организации; admin — все.',
   'поддержка тикеты support desk SLA эскалация CSAT KB внутренние заметки')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Тикеты поддержки (Support Desk)');
