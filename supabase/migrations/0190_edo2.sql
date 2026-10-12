-- ============================================================
-- 3DMP Service · 0190_edo2.sql  (X7 — ЭДО 2.0)
-- Внешний обмен (app_edo_exchange), SLA поручений, папки/дела (app_doc_folders),
-- подписи документов (reuse app_signatures W17), маршруты документов (reuse W10),
-- дашборд ЭДО. Идемпотентно. Зависит от 0001..0189.
-- ============================================================

create table if not exists public.app_edo_exchange (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  doc_id        uuid references public.app_doc_flows (id) on delete cascade,
  counterparty  text,
  operator      text,                        -- ЭДО-оператор (Диадок/СБИС/…)
  incoming_ref  text,
  status        text not null default 'queued',  -- queued|sent|delivered|accepted|rejected|error
  sent_at       timestamptz,
  accepted_at   timestamptz,
  note          text,
  created_login text,
  created_at    timestamptz not null default now()
);
create index if not exists app_edo_exchange_idx on public.app_edo_exchange (tenant_id, status);
alter table public.app_edo_exchange enable row level security;

create table if not exists public.app_doc_folders (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  parent_id   uuid references public.app_doc_folders (id) on delete set null,
  name        text not null,
  code        text,
  note        text,
  created_at  timestamptz not null default now()
);
create index if not exists app_doc_folders_idx on public.app_doc_folders (tenant_id, parent_id);
alter table public.app_doc_folders enable row level security;

alter table public.app_doc_resolutions add column if not exists due_at timestamptz;
alter table public.app_doc_resolutions add column if not exists sla_minutes integer;
alter table public.app_doc_flows       add column if not exists folder_id uuid references public.app_doc_folders (id) on delete set null;
alter table public.app_doc_flows       add column if not exists signature_method text;

-- ================= RPC: внешний обмен =================
create or replace function public.app_edo_send_ext(p_token uuid, p_doc_id uuid, p_counterparty text, p_operator text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; d record; iid uuid; newid uuid; op text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  if not public.app_can_edit(p_token, 'edo') then return query select false,'Нет прав на ЭДО', null::uuid; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  select * into d from public.app_doc_flows where id = p_doc_id and (public.app_is_platform_admin(p_token) or tenant_id = ten);
  if d.id is null then return query select false,'Документ не найден', null::uuid; return; end if;
  op := coalesce(nullif(trim(p_operator),''), 'ЭДО-оператор');
  insert into public.app_edo_exchange (tenant_id, doc_id, counterparty, operator, status, created_login)
  values (ten, p_doc_id, nullif(trim(p_counterparty),''), op, 'queued', uname)
  returning app_edo_exchange.id into newid;
  select i.id into iid from public.app_integrations i
   where i.tenant_id = ten and coalesce(i.active,true) and i.kind = 'edo' order by i.created_at limit 1;
  if iid is not null then
    perform public.app_integration_enqueue(p_token, iid, 'out', jsonb_build_object(
      'kind','edo','doc_id',p_doc_id,'reg_number',d.reg_number,'title',d.title,
      'counterparty',coalesce(p_counterparty, d.correspondent),'operator',op));
    update public.app_edo_exchange set status='sent', sent_at=now() where id = newid;
    return query select true,'Документ поставлен в очередь ЭДО-оператора (' || op || ')', newid;
  end if;
  return query select true,'Обмен создан (интеграция ЭДО не настроена — статус queued)', newid;
end $$;

create or replace function public.app_edo_exchange_list(p_token uuid, p_doc_id uuid default null)
returns table (id uuid, doc_number text, doc_title text, counterparty text, operator text, status text, sent_at timestamptz, accepted_at timestamptz, note text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select e.id, d.reg_number, d.title, e.counterparty, e.operator, e.status, e.sent_at, e.accepted_at, e.note
      from public.app_edo_exchange e left join public.app_doc_flows d on d.id = e.doc_id
     where (adm or e.tenant_id = ten) and (p_doc_id is null or e.doc_id = p_doc_id)
     order by e.created_at desc;
end $$;

create or replace function public.app_edo_exchange_set_status(p_token uuid, p_id uuid, p_status text, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; st text; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  if not public.app_can_edit(p_token, 'edo') then return query select false,'Нет прав на ЭДО'; return; end if;
  ten := public.app_my_tenant(p_token);
  st := lower(trim(coalesce(p_status,'')));
  if st not in ('queued','sent','delivered','accepted','rejected','error') then return query select false,'Недопустимый статус'; return; end if;
  update public.app_edo_exchange e set status = st,
         accepted_at = case when st='accepted' then now() else e.accepted_at end,
         note = coalesce(nullif(trim(p_note),''), e.note)
   where e.id = p_id and (public.app_is_platform_admin(p_token) or e.tenant_id = ten);
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Обмен не найден'; return; end if;
  return query select true,'Статус обмена: ' || st;
end $$;

-- ================= RPC: SLA поручений =================
create or replace function public.app_doc_resolution_set_sla(p_token uuid, p_id uuid, p_due_at timestamptz, p_sla_minutes integer)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  if not public.app_can_edit(p_token, 'edo') then return query select false,'Нет прав на ЭДО'; return; end if;
  ten := public.app_my_tenant(p_token);
  update public.app_doc_resolutions r set due_at = p_due_at, sla_minutes = p_sla_minutes
   where r.id = p_id and (public.app_is_platform_admin(p_token) or r.tenant_id = ten);
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Поручение не найдено'; return; end if;
  return query select true,'SLA поручения обновлён';
end $$;

create or replace function public.app_edo_resolution_scan(p_token uuid)
returns table (notified integer, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; rec record; cnt integer := 0; au uuid;
begin
  if not public.app_production_allowed(p_token) then return query select 0,'Доступ запрещён'; return; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  for rec in
    select r.id, r.text, r.assignee_login, r.author_login, r.due_at, r.due_date, d.reg_number, d.title
      from public.app_doc_resolutions r join public.app_doc_flows d on d.id = r.doc_id
     where (adm or r.tenant_id = ten) and r.status = 'open'
       and ((r.due_at is not null and r.due_at < now())
         or (r.due_at is null and r.due_date is not null and r.due_date < current_date))
  loop
    au := null;
    if rec.assignee_login is not null then
      select u.id into au from public.app_users u where u.login = rec.assignee_login and u.tenant_id = ten limit 1;
    end if;
    if au is not null then
      perform public.app_notif_send(au, 'Просрочено поручение', left(rec.text,180) || ' (док. ' || coalesce(rec.reg_number,'—') || ')', 'apps/edo/index.html');
    end if;
    perform public.app_notif_roles_t(ten, array['admin','owner','manager'], 'ЭДО: просрочено поручение', left(rec.text,180), 'apps/edo/index.html');
    cnt := cnt + 1;
  end loop;
  return query select cnt, 'Просроченных поручений: ' || cnt;
end $$;

-- ================= RPC: подписи документа =================
create or replace function public.app_doc_sign(p_token uuid, p_doc_id uuid, p_method text, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; meth text; d record;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  select * into d from public.app_doc_flows where id = p_doc_id and (public.app_is_platform_admin(p_token) or tenant_id = ten);
  if d.id is null then return query select false,'Документ не найден'; return; end if;
  meth := coalesce(nullif(trim(p_method),''),'ПЭП');
  if meth not in ('ПЭП','УНЭП','УКЭП','Госключ') then return query select false,'Метод: ПЭП/УНЭП/УКЭП/Госключ'; return; end if;
  insert into public.app_signatures (tenant_id, entity_type, entity_id, signer_login, method, status, note)
  values (ten, 'doc_flow', p_doc_id, uname, meth, 'signed', nullif(trim(p_note),''));
  update public.app_doc_flows set signature_method = meth, updated_at = now() where id = p_doc_id;
  return query select true,'Документ подписан (' || meth || ')';
end $$;

create or replace function public.app_doc_signatures_list(p_token uuid, p_doc_id uuid)
returns table (id uuid, signer_login text, method text, status text, signed_at timestamptz, note text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select s.id, s.signer_login, s.method, s.status, s.signed_at, s.note
      from public.app_signatures s
     where s.entity_type = 'doc_flow' and s.entity_id = p_doc_id and (adm or s.tenant_id = ten)
     order by s.signed_at desc;
end $$;

-- ================= RPC: маршруты документов (reuse W10) =================
create or replace function public.app_doc_route_start(p_token uuid, p_doc_id uuid, p_route_id uuid)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; d record; r record;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  if not public.app_can_edit(p_token, 'edo') then return query select false,'Нет прав на ЭДО', null::uuid; return; end if;
  ten := public.app_my_tenant(p_token);
  select * into d from public.app_doc_flows where id = p_doc_id and (public.app_is_platform_admin(p_token) or tenant_id = ten);
  if d.id is null then return query select false,'Документ не найден', null::uuid; return; end if;
  select * into r from public.app_approval_request_create(p_token, p_route_id, 'doc_flow', p_doc_id, d.title) x;
  if not r.ok then return query select false, r.message, null::uuid; return; end if;
  return query select true, 'Документ запущен по маршруту', r.id;
end $$;

create or replace function public.app_doc_route_act(p_token uuid, p_request_id uuid, p_action text, p_comment text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; r record; req record;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  select * into req from public.app_approval_requests where id = p_request_id and (public.app_is_platform_admin(p_token) or tenant_id = ten);
  if req.id is null then return query select false,'Заявка не найдена'; return; end if;
  select * into r from public.app_approval_act(p_token, p_request_id, p_action, p_comment) x;
  if not r.ok then return query select false, r.message; return; end if;
  if req.entity_type = 'doc_flow' and req.entity_id is not null and r.message like '%Заявка согласована%' then
    update public.app_doc_flows set status = case when status in ('closed','cancelled') then status else 'in_work' end, updated_at = now() where id = req.entity_id;
  end if;
  return query select true, r.message;
end $$;

-- ================= RPC: папки/дела =================
create or replace function public.app_doc_folder_list(p_token uuid)
returns table (id uuid, parent_id uuid, name text, code text, docs bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select f.id, f.parent_id, f.name, f.code,
           (select count(*) from public.app_doc_flows d where d.folder_id = f.id)
      from public.app_doc_folders f where adm or f.tenant_id = ten order by f.name;
end $$;

create or replace function public.app_doc_folder_save(p_token uuid, p_id uuid, p_name text, p_code text, p_parent_id uuid)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  if not public.app_can_edit(p_token, 'edo') then return query select false,'Нет прав на ЭДО', null::uuid; return; end if;
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if coalesce(trim(p_name),'') = '' then return query select false,'Укажите название папки', null::uuid; return; end if;
  if p_id is null then
    insert into public.app_doc_folders (tenant_id, parent_id, name, code)
    values (ten, p_parent_id, left(trim(p_name),160), nullif(trim(p_code),''))
    returning app_doc_folders.id into newid;
    return query select true,'Папка создана', newid;
  else
    update public.app_doc_folders f set parent_id = p_parent_id, name = left(trim(p_name),160), code = nullif(trim(p_code),'')
     where f.id = p_id and (public.app_is_platform_admin(p_token) or f.tenant_id = ten)
     returning f.id into newid;
    if newid is null then return query select false,'Папка не найдена', null::uuid; return; end if;
    return query select true,'Папка сохранена', newid;
  end if;
end $$;

create or replace function public.app_edo_resolutions_open(p_token uuid)
returns table (id uuid, doc_number text, doc_title text, body text, assignee_login text, due_at timestamptz, due_date date, overdue boolean, status text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select r.id, d.reg_number, d.title, r.text, r.assignee_login, r.due_at, r.due_date,
           ((r.due_at is not null and r.due_at < now()) or (r.due_at is null and r.due_date is not null and r.due_date < current_date)),
           r.status
      from public.app_doc_resolutions r join public.app_doc_flows d on d.id = r.doc_id
     where (adm or r.tenant_id = ten) and r.status = 'open'
     order by r.due_at nulls last, r.due_date nulls last;
end $$;

create or replace function public.app_edo_dashboard(p_token uuid)
returns table (total bigint, registered bigint, in_work bigint, closed bigint, overdue bigint,
               exchange_queue bigint, exchange_sent bigint, exchange_accepted bigint, resolutions_open bigint, resolutions_overdue bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select
    (select count(*) from public.app_doc_flows d where adm or d.tenant_id=ten),
    (select count(*) from public.app_doc_flows d where (adm or d.tenant_id=ten) and d.status='registered'),
    (select count(*) from public.app_doc_flows d where (adm or d.tenant_id=ten) and d.status='in_work'),
    (select count(*) from public.app_doc_flows d where (adm or d.tenant_id=ten) and d.status='closed'),
    (select count(*) from public.app_doc_flows d where (adm or d.tenant_id=ten) and d.due_date < current_date and d.status not in ('closed','cancelled')),
    (select count(*) from public.app_edo_exchange e where (adm or e.tenant_id=ten) and e.status='queued'),
    (select count(*) from public.app_edo_exchange e where (adm or e.tenant_id=ten) and e.status='sent'),
    (select count(*) from public.app_edo_exchange e where (adm or e.tenant_id=ten) and e.status='accepted'),
    (select count(*) from public.app_doc_resolutions r where (adm or r.tenant_id=ten) and r.status='open'),
    (select count(*) from public.app_doc_resolutions r where (adm or r.tenant_id=ten) and r.status='open'
       and ((r.due_at is not null and r.due_at < now()) or (r.due_at is null and r.due_date < current_date)));
end $$;

-- ================= Демо =================
insert into public.app_approval_routes (tenant_id, name, doc_type, steps, active, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'Согласование документа: юрист → директор', 'doc_flow',
       '[{"ord":1,"role":"manager","name":"Юрист"},{"ord":2,"role":"director","name":"Директор"}]'::jsonb, true, 'owner'
where not exists (select 1 from public.app_approval_routes where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and doc_type='doc_flow');

-- ================= База знаний =================
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','ЭДО 2.0: внешний обмен, SLA поручений, подписи, папки (X7)',
   'ЭДО 2.0: внешний обмен с контрагентами (app_edo_exchange — статусы queued→sent→delivered→accepted/rejected/error; app_edo_send_ext ставит документ в очередь активной интеграции ЭДО-оператора, app_edo_exchange_list/set_status), SLA поручений (app_doc_resolutions.due_at/sla_minutes, app_doc_resolution_set_sla, app_edo_resolution_scan — уведомления о просрочке), подписи документов (app_doc_sign/документ подписывается методом ПЭП/УНЭП/УКЭП/Госключ, запись в app_signatures W17; app_doc_signatures_list), маршруты документов (app_doc_route_start/route_act — reuse движка согласований W10), папки/дела (app_doc_folders + app_doc_flows.folder_id; app_doc_folder_list/save), дашборд app_edo_dashboard.',
   'ЭДО внешний обмен контрагент оператор SLA поручение подпись УКЭП Госключ маршрут папка дело')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001'
     and question = 'ЭДО 2.0: внешний обмен, SLA поручений, подписи, папки (X7)'
);

-- ================= Права =================
grant execute on function public.app_edo_send_ext(uuid,uuid,text,text) to anon, authenticated;
grant execute on function public.app_edo_exchange_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_edo_exchange_set_status(uuid,uuid,text,text) to anon, authenticated;
grant execute on function public.app_doc_resolution_set_sla(uuid,uuid,timestamptz,integer) to anon, authenticated;
grant execute on function public.app_edo_resolution_scan(uuid) to anon, authenticated;
grant execute on function public.app_edo_resolutions_open(uuid) to anon, authenticated;
grant execute on function public.app_doc_sign(uuid,uuid,text,text) to anon, authenticated;
grant execute on function public.app_doc_signatures_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_doc_route_start(uuid,uuid,uuid) to anon, authenticated;
grant execute on function public.app_doc_route_act(uuid,uuid,text,text) to anon, authenticated;
grant execute on function public.app_doc_folder_list(uuid) to anon, authenticated;
grant execute on function public.app_doc_folder_save(uuid,uuid,text,text,uuid) to anon, authenticated;
grant execute on function public.app_edo_dashboard(uuid) to anon, authenticated;
