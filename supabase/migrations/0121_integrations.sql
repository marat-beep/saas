-- ============================================================
-- 3DMP Service · 0121_integrations.sql  (W6 — Интеграции)
-- Конфигуратор интеграций (1С/ERP/OData, e-mail/SMTP, Telegram/SMS, ЭДО),
-- журнал обмена и ретраи. Идемпотентно. Зависит от 0001..0120.
-- ============================================================

create table if not exists public.app_integrations (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  name          text not null,
  kind          text not null default 'odata',   -- odata|smtp|telegram|sms|edo|webhook
  direction     text not null default 'out',      -- in|out|both
  endpoint      text,
  token         text,
  settings      jsonb not null default '{}'::jsonb,
  active        boolean not null default true,
  max_retries   integer not null default 3,
  last_run      timestamptz,
  last_status   text,
  created_by    uuid references public.app_users (id) on delete set null,
  created_login text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists app_integrations_idx on public.app_integrations (tenant_id, active);

create table if not exists public.app_integration_log (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid references public.tenants (id),
  integration_id uuid references public.app_integrations (id) on delete cascade,
  kind           text,
  direction      text,
  status         text not null default 'pending',   -- pending|ok|error|failed
  retry_count    integer not null default 0,
  max_retries    integer not null default 3,
  payload        jsonb,
  response       text,
  message        text,
  next_retry_at  timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index if not exists app_integration_log_idx on public.app_integration_log (tenant_id, created_at desc);
create index if not exists app_integration_log_pending_idx on public.app_integration_log (status, next_retry_at);

alter table public.app_integrations    enable row level security;
alter table public.app_integration_log enable row level security;

-- ---------- Список интеграций ----------
drop function if exists public.app_integrations_list(uuid);
create or replace function public.app_integrations_list(p_token uuid)
returns table (id uuid, name text, kind text, direction text, endpoint text, active boolean, max_retries integer,
               has_token boolean, last_run timestamptz, last_status text, logs_total bigint, logs_failed bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; urole text; ten uuid;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Доступ запрещён'; end if;
  if not public.app_can(p_token, 'integrations', 'view') then raise exception 'Нет прав'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select i.id, i.name, i.kind, i.direction, i.endpoint, i.active, i.max_retries,
           (i.token is not null and i.token <> ''), i.last_run, i.last_status,
           (select count(*) from public.app_integration_log l where l.integration_id = i.id),
           (select count(*) from public.app_integration_log l where l.integration_id = i.id and l.status in ('error','failed'))
      from public.app_integrations i
     where (urole = 'admin' or i.tenant_id = ten)
     order by i.created_at desc;
end $$;

-- ---------- Сохранить интеграцию ----------
drop function if exists public.app_integration_save(uuid,uuid,text,text,text,text,text,jsonb,boolean,integer);
create or replace function public.app_integration_save(
  p_token uuid, p_id uuid, p_name text, p_kind text, p_direction text, p_endpoint text, p_token_secret text,
  p_settings jsonb, p_active boolean, p_max_retries integer
) returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ten uuid; iid uuid; k text;
begin
  select s.uid into uid from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна', null::uuid; return; end if;
  if not public.app_can(p_token, 'integrations', 'edit') then return query select false, 'Нет прав', null::uuid; return; end if;
  if coalesce(trim(p_name), '') = '' then return query select false, 'Укажите название', null::uuid; return; end if;
  k := coalesce(nullif(trim(p_kind),''),'odata');
  if k not in ('odata','smtp','telegram','sms','edo','webhook') then return query select false, 'Неизвестный тип интеграции', null::uuid; return; end if;
  ten := public.app_my_tenant(p_token);
  if p_id is null then
    insert into public.app_integrations (tenant_id, name, kind, direction, endpoint, token, settings, active, max_retries, created_by, created_login)
    values (ten, trim(p_name), k, coalesce(nullif(trim(p_direction),''),'out'), nullif(trim(p_endpoint),''),
            nullif(trim(p_token_secret),''), coalesce(p_settings, '{}'::jsonb), coalesce(p_active,true), coalesce(p_max_retries,3), uid,
            (select ulogin from public.app_session_user(p_token)))
    returning app_integrations.id into iid;
  else
    update public.app_integrations i
       set name = trim(p_name), kind = k, direction = coalesce(nullif(trim(p_direction),''), i.direction),
           endpoint = nullif(trim(p_endpoint),''),
           token = case when p_token_secret is null or trim(p_token_secret) = '' then i.token else trim(p_token_secret) end,
           settings = coalesce(p_settings, i.settings), active = coalesce(p_active, i.active),
           max_retries = coalesce(p_max_retries, i.max_retries), updated_at = now()
     where i.id = p_id and (public.app_is_platform_admin(p_token) or i.tenant_id = ten);
    if not found then return query select false, 'Интеграция не найдена', null::uuid; return; end if;
    iid := p_id;
  end if;
  return query select true, 'Интеграция сохранена', iid;
end $$;

drop function if exists public.app_integration_delete(uuid,uuid);
create or replace function public.app_integration_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ten uuid;
begin
  select s.uid into uid from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна'; return; end if;
  if not public.app_can(p_token, 'integrations', 'edit') then return query select false, 'Нет прав'; return; end if;
  ten := public.app_my_tenant(p_token);
  delete from public.app_integrations i
   where i.id = p_id and (public.app_is_platform_admin(p_token) or i.tenant_id = ten);
  if not found then return query select false, 'Интеграция не найдена'; return; end if;
  return query select true, 'Интеграция удалена';
end $$;

-- ---------- Поставить обмен в очередь ----------
drop function if exists public.app_integration_enqueue(uuid,uuid,text,jsonb);
create or replace function public.app_integration_enqueue(p_token uuid, p_id uuid, p_direction text default 'out', p_payload jsonb default null)
returns table (ok boolean, message text, log_id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ten uuid; integ record; lid uuid;
begin
  select s.uid into uid from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна', null::uuid; return; end if;
  if not public.app_can(p_token, 'integrations', 'edit') then return query select false, 'Нет прав', null::uuid; return; end if;
  ten := public.app_my_tenant(p_token);
  select * into integ from public.app_integrations i
   where i.id = p_id and (public.app_is_platform_admin(p_token) or i.tenant_id = ten);
  if integ.id is null then return query select false, 'Интеграция не найдена', null::uuid; return; end if;
  insert into public.app_integration_log (tenant_id, integration_id, kind, direction, status, max_retries, payload, next_retry_at)
  values (integ.tenant_id, integ.id, integ.kind, coalesce(nullif(trim(p_direction),''),'out'), 'pending', integ.max_retries, p_payload, now())
  returning app_integration_log.id into lid;
  return query select true, 'Обмен поставлен в очередь', lid;
end $$;

-- ---------- Обработать очередь (имитация обмена + ретраи) ----------
drop function if exists public.app_integration_process(uuid,integer);
create or replace function public.app_integration_process(p_token uuid, p_limit integer default 50)
returns table (processed integer, ok_count integer, err_count integer, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; urole text; ten uuid; r record; pr int := 0; okc int := 0; errc int := 0; good boolean; newretry int;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then return query select 0,0,0,'Сессия недействительна'; return; end if;
  if not public.app_can(p_token, 'integrations', 'edit') then return query select 0,0,0,'Нет прав'; return; end if;
  ten := public.app_my_tenant(p_token);
  for r in
    select l.id, l.retry_count, l.max_retries, l.tenant_id, i.active, i.endpoint, i.id as iid
      from public.app_integration_log l join public.app_integrations i on i.id = l.integration_id
     where l.status in ('pending','error') and (l.next_retry_at is null or l.next_retry_at <= now())
       and (urole = 'admin' or l.tenant_id = ten)
     order by l.created_at
     limit greatest(1, least(coalesce(p_limit,50),200))
  loop
    good := r.active and coalesce(trim(r.endpoint), '') <> '';
    newretry := r.retry_count + (case when good then 0 else 1 end);
    if good then
      update public.app_integration_log set status='ok', response='Доставлено (имитация)', message=null, updated_at=now() where id=r.id;
      update public.app_integrations set last_run=now(), last_status='ok' where id=r.iid;
      okc := okc + 1;
    else
      update public.app_integration_log set
        status = case when newretry >= r.max_retries then 'failed' else 'error' end,
        retry_count = newretry,
        message = case when not r.active then 'Интеграция отключена' else 'Не задан endpoint' end,
        next_retry_at = case when newretry < r.max_retries then now() + interval '5 minutes' else null end,
        updated_at = now()
       where id = r.id;
      update public.app_integrations set last_run=now(), last_status='error' where id=r.iid;
      errc := errc + 1;
    end if;
    pr := pr + 1;
  end loop;
  return query select pr, okc, errc, case when pr = 0 then 'Нет обменов в очереди' else 'Обработано: ' || pr end;
end $$;

-- ---------- Повторить запись журнала вручную ----------
drop function if exists public.app_integration_retry(uuid,uuid);
create or replace function public.app_integration_retry(p_token uuid, p_log_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ten uuid;
begin
  select s.uid into uid from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна'; return; end if;
  if not public.app_can(p_token, 'integrations', 'edit') then return query select false, 'Нет прав'; return; end if;
  ten := public.app_my_tenant(p_token);
  update public.app_integration_log l
     set status='pending', next_retry_at=now(), message='Повтор вручную', updated_at=now()
   where l.id = p_log_id and l.status in ('error','failed')
     and (public.app_is_platform_admin(p_token) or l.tenant_id = ten);
  if not found then return query select false, 'Запись не найдена или не требует повтора'; return; end if;
  return query select true, 'Запись поставлена на повтор';
end $$;

-- ---------- Журнал обмена ----------
drop function if exists public.app_integration_log_list(uuid,uuid,integer);
create or replace function public.app_integration_log_list(p_token uuid, p_integration_id uuid default null, p_limit integer default 100)
returns table (id uuid, integration_id uuid, integration text, kind text, direction text, status text,
               retry_count integer, max_retries integer, message text, response text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; urole text; ten uuid;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Доступ запрещён'; end if;
  if not public.app_can(p_token, 'integrations', 'view') then raise exception 'Нет прав'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select l.id, l.integration_id, i.name, l.kind, l.direction, l.status, l.retry_count, l.max_retries, l.message, l.response, l.created_at
      from public.app_integration_log l
      left join public.app_integrations i on i.id = l.integration_id
     where (urole = 'admin' or l.tenant_id = ten)
       and (p_integration_id is null or l.integration_id = p_integration_id)
     order by l.created_at desc
     limit greatest(1, least(coalesce(p_limit,100),500));
end $$;

-- ---------- KPI ----------
drop function if exists public.app_integrations_kpi(uuid);
create or replace function public.app_integrations_kpi(p_token uuid)
returns table (total bigint, active bigint, ok_count bigint, err_count bigint, pending bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; urole text; ten uuid;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select
      (select count(*) from public.app_integrations i where (urole='admin' or i.tenant_id=ten)),
      (select count(*) from public.app_integrations i where i.active and (urole='admin' or i.tenant_id=ten)),
      (select count(*) from public.app_integration_log l where l.status='ok' and (urole='admin' or l.tenant_id=ten)),
      (select count(*) from public.app_integration_log l where l.status in ('error','failed') and (urole='admin' or l.tenant_id=ten)),
      (select count(*) from public.app_integration_log l where l.status='pending' and (urole='admin' or l.tenant_id=ten));
end $$;

grant execute on function public.app_integrations_list(uuid)                                   to anon, authenticated;
grant execute on function public.app_integration_save(uuid,uuid,text,text,text,text,text,jsonb,boolean,integer) to anon, authenticated;
grant execute on function public.app_integration_delete(uuid,uuid)                             to anon, authenticated;
grant execute on function public.app_integration_enqueue(uuid,uuid,text,jsonb)                 to anon, authenticated;
grant execute on function public.app_integration_process(uuid,integer)                         to anon, authenticated;
grant execute on function public.app_integration_retry(uuid,uuid)                              to anon, authenticated;
grant execute on function public.app_integration_log_list(uuid,uuid,integer)                   to anon, authenticated;
grant execute on function public.app_integrations_kpi(uuid)                                    to anon, authenticated;

-- ---------- Права (матрица) ----------
insert into public.app_role_permissions (id, tenant_id, role, module_id, can_view, can_edit)
select gen_random_uuid(), null, v.role, 'integrations', true, v.edit
from (values ('admin', true), ('owner', true), ('manager', false), ('director', false)) as v(role, edit)
where not exists (
  select 1 from public.app_role_permissions p where p.module_id = 'integrations' and p.role = v.role and p.tenant_id is null
);

-- ---------- Демо-данные (тенант A) ----------
insert into public.app_integrations (tenant_id, name, kind, direction, endpoint, token, settings, active, max_retries, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.name, v.kind, v.direction, v.endpoint, v.token, v.settings::jsonb, v.active, v.max_retries, 'admin'
from (values
  ('Telegram — оповещения', 'telegram', 'out', 'https://api.telegram.org/bot{token}/sendMessage', 'demo-token', '{"chat_id":"-1000000000"}', true, 3),
  ('1С/ERP — обмен заказами', 'odata', 'both', 'https://erp.example.local/odata/standard.odata', 'demo-user:demo-pass', '{"entity":"Document_ЗаказКлиента"}', true, 3),
  ('E-mail — SMTP рассылки', 'smtp', 'out', 'smtp://smtp.example.local:587', '', '{"from":"erp@example.local","tls":true}', true, 3)
) as v(name,kind,direction,endpoint,token,settings,active,max_retries)
where not exists (
  select 1 from public.app_integrations i
   where i.tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and i.name = v.name
);

-- демо-журнал обмена (одна успешная, одна с ошибкой для демонстрации ретраев)
insert into public.app_integration_log (tenant_id, integration_id, kind, direction, status, retry_count, max_retries, response, message)
select i.tenant_id, i.id, i.kind, 'out', 'ok', 0, i.max_retries, 'Доставлено (имитация)', null
from public.app_integrations i
where i.tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and i.name = 'Telegram — оповещения'
  and not exists (select 1 from public.app_integration_log l where l.integration_id = i.id);

insert into public.app_integration_log (tenant_id, integration_id, kind, direction, status, retry_count, max_retries, message)
select i.tenant_id, i.id, i.kind, 'out', 'error', 1, i.max_retries, 'Не задан endpoint'
from public.app_integrations i
where i.tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and i.name = 'E-mail — SMTP рассылки'
  and not exists (select 1 from public.app_integration_log l where l.integration_id = i.id);

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Интеграции (1С/ERP, e-mail, Telegram/SMS, ЭДО)',
   'Конфигуратор интеграций: организации и платформы. Типы: odata (1С/ERP), smtp (e-mail), telegram, sms, edo (ЭДО), webhook. Для каждой интеграции — endpoint, токен, настройки (jsonb), направление, максимальное число ретраев. Обмен ставится в очередь (app_integration_enqueue) и обрабатывается (app_integration_process) с ретраями: при ошибке запись остаётся в статусе pending до max_retries, затем failed; журнал — app_integration_log_list, ручной повтор — app_integration_retry. Реальная отправка выполняется серверным воркером/Edge (по образцу backend-example/, allow-list/токен); в интерфейсе — конфигурация, очередь и журнал.',
   'интеграции 1С ERP OData SMTP e-mail Telegram SMS ЭДО webhook журнал ретраи коннектор')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and question = 'Интеграции (1С/ERP, e-mail, Telegram/SMS, ЭДО)'
);
