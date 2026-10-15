-- ============================================================
-- 3DMP Service · 0262_marketing.sql  (R4 · PROP-28 — маркетинг/кампании и контакт-центр)
-- Кампании (каналы/сегменты/отклик) + входящие обращения (контакт-центр, SLA). Идемпотентно.
-- ============================================================

create table if not exists public.app_campaigns (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  name text not null,
  channel text,
  segment text,
  status text not null default 'planned', -- planned|active|done|paused
  planned_date date,
  budget numeric,
  sent int default 0,
  response int default 0,
  note text,
  created_login text,
  created_at timestamptz not null default now()
);
create index if not exists app_campaigns_idx on public.app_campaigns (tenant_id, status);

create table if not exists public.app_inbox (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  channel text,                     -- phone|email|telegram|whatsapp|chat|site
  contact text,                     -- кто обратился
  subject text,
  body text,
  status text not null default 'new',  -- new|in_work|closed
  priority text default 'normal',      -- low|normal|high
  assignee text,
  due_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists app_inbox_idx on public.app_inbox (tenant_id, status);

-- ---------- Кампании ----------
create or replace function public.app_campaign_list(p_token uuid)
returns table (id uuid, name text, channel text, segment text, status text, planned_date date, budget numeric, sent int, response int, note text)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select c.id, c.name, c.channel, c.segment, c.status, c.planned_date, c.budget, c.sent, c.response, c.note
    from public.app_campaigns c where (urole = 'admin' or c.tenant_id = ten) order by c.created_at desc;
end $$;
grant execute on function public.app_campaign_list(uuid) to anon, authenticated;

create or replace function public.app_campaign_save(p_token uuid, p_id uuid, p_name text, p_channel text, p_segment text, p_status text, p_planned_date date, p_budget numeric, p_sent int, p_response int, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid; rid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_name), '') = '' then return query select false, 'Укажите название'; return; end if;
  if p_id is null then
    insert into public.app_campaigns (tenant_id, name, channel, segment, status, planned_date, budget, sent, response, note, created_login)
    values (ten, p_name, p_channel, p_segment, coalesce(p_status, 'planned'), p_planned_date, p_budget, coalesce(p_sent, 0), coalesce(p_response, 0), p_note, (select ulogin from public.app_session_user(p_token))) returning id into rid;
  else
    update public.app_campaigns set name = p_name, channel = p_channel, segment = p_segment, status = coalesce(p_status, status),
      planned_date = p_planned_date, budget = p_budget, sent = coalesce(p_sent, 0), response = coalesce(p_response, 0), note = p_note
      where id = p_id and (urole = 'admin' or tenant_id = ten) returning id into rid;
  end if;
  if rid is null then return query select false, 'Не найдено'; return; end if;
  return query select true, 'Сохранено';
end $$;
grant execute on function public.app_campaign_save(uuid,uuid,text,text,text,text,date,numeric,int,int,text) to anon, authenticated;

create or replace function public.app_campaign_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_campaigns where id = p_id and (urole = 'admin' or tenant_id = ten);
  return query select true, 'Удалено';
end $$;
grant execute on function public.app_campaign_delete(uuid,uuid) to anon, authenticated;

-- ---------- Контакт-центр (входящие обращения) ----------
create or replace function public.app_inbox_list(p_token uuid)
returns table (id uuid, channel text, contact text, subject text, status text, priority text, assignee text, due_at timestamptz, created_at timestamptz)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select i.id, i.channel, i.contact, i.subject, i.status, i.priority, i.assignee, i.due_at, i.created_at
    from public.app_inbox i where (urole = 'admin' or i.tenant_id = ten) order by i.created_at desc;
end $$;
grant execute on function public.app_inbox_list(uuid) to anon, authenticated;

create or replace function public.app_inbox_add(p_token uuid, p_channel text, p_contact text, p_subject text, p_body text, p_priority text, p_sla_hours int, p_assignee text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public as $$
declare ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  insert into public.app_inbox (tenant_id, channel, contact, subject, body, priority, assignee, due_at)
  values (ten, p_channel, p_contact, p_subject, p_body, coalesce(p_priority, 'normal'), p_assignee, now() + make_interval(hours => greatest(coalesce(p_sla_hours, 24), 1)));
  return query select true, 'Обращение зарегистрировано';
end $$;
grant execute on function public.app_inbox_add(uuid,text,text,text,text,text,int,text) to anon, authenticated;

create or replace function public.app_inbox_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  update public.app_inbox set status = p_status where id = p_id and (urole = 'admin' or tenant_id = ten);
  return query select true, 'Статус обновлён';
end $$;
grant execute on function public.app_inbox_set_status(uuid,uuid,text) to anon, authenticated;
