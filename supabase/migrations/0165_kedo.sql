-- ============================================================
-- 3DMP Service · 0165_kedo.sql  (W20 — КЭДО)
-- Кадровый ЭДО: документы (приказы/заявления/ознакомления), шаблоны, личный кабинет,
-- МЧД, подписание (задел под ПЭП/УНЭП/УКЭП/Госключ). Идемпотентно. Зависит от 0001..0164.
-- ============================================================

create table if not exists public.app_hr_docs (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid references public.tenants (id),
  employee_login text,
  doc_type       text not null default 'other',   -- hire|transfer|dismiss|vacation|sick|ack|order|other
  title          text not null,
  number         text,
  status         text not null default 'draft',    -- draft|sent|signed|declined|archived
  payload        jsonb not null default '{}'::jsonb,
  signed_at      timestamptz,
  signed_by      uuid references public.app_users (id) on delete set null,
  sign_method    text,
  comment        text,
  created_login  text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index if not exists app_hr_docs_idx on public.app_hr_docs (tenant_id, employee_login, status);
alter table public.app_hr_docs enable row level security;

create table if not exists public.app_hr_doc_templates (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  code        text,
  name        text not null,
  doc_type    text,
  body        text,
  created_at  timestamptz not null default now()
);
alter table public.app_hr_doc_templates enable row level security;

create table if not exists public.app_mchd (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid references public.tenants (id),
  number           text,
  issued_to_login  text,
  authority        text,
  valid_from       date,
  valid_to         date,
  status           text not null default 'active',  -- active|revoked|expired
  note             text,
  created_login    text,
  created_at       timestamptz not null default now()
);
create index if not exists app_mchd_idx on public.app_mchd (tenant_id, status);
alter table public.app_mchd enable row level security;

-- ---------- RPC: кадровые документы ----------
create or replace function public.app_hr_docs_list(p_token uuid, p_status text default null, p_type text default null, p_employee text default null)
returns table (id uuid, employee_login text, doc_type text, title text, number text, status text, signed_at timestamptz, sign_method text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean; st text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  st := nullif(trim(coalesce(p_status,'')),'');
  return query
    select d.id, d.employee_login, d.doc_type, d.title, d.number, d.status, d.signed_at, d.sign_method, d.created_at
      from public.app_hr_docs d
     where (adm or d.tenant_id = ten)
       and (st is null or d.status = st)
       and (p_type is null or p_type='' or d.doc_type = p_type)
       and (p_employee is null or p_employee='' or d.employee_login = p_employee)
     order by d.created_at desc;
end $$;

create or replace function public.app_hr_doc_save(p_token uuid, p_id uuid, p_employee text, p_doc_type text, p_title text, p_payload jsonb)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; newid uuid; tp text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if coalesce(trim(p_title),'') = '' then return query select false,'Укажите название документа', null::uuid; return; end if;
  if coalesce(trim(p_employee),'') = '' then return query select false,'Укажите сотрудника', null::uuid; return; end if;
  tp := coalesce(nullif(trim(p_doc_type),''),'other');
  if p_id is null then
    insert into public.app_hr_docs (tenant_id, employee_login, doc_type, title, payload, status, created_login)
    values (ten, trim(p_employee), tp, left(trim(p_title),200), coalesce(p_payload,'{}'::jsonb), 'draft', uname)
    returning app_hr_docs.id into newid;
    return query select true,'Кадровый документ создан', newid;
  else
    update public.app_hr_docs d set employee_login = trim(p_employee), doc_type = tp, title = left(trim(p_title),200),
           payload = coalesce(p_payload, d.payload), updated_at = now()
     where d.id = p_id and d.status in ('draft','declined') and (public.app_is_platform_admin(p_token) or d.tenant_id = ten)
     returning d.id into newid;
    if newid is null then return query select false,'Документ не найден или уже отправлен', null::uuid; return; end if;
    return query select true,'Кадровый документ сохранён', newid;
  end if;
end $$;

create or replace function public.app_hr_doc_sign(p_token uuid, p_id uuid, p_action text, p_comment text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uid uuid; uname text; act text; d record; au uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.uid, s.ulogin into uid, uname from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  act := lower(trim(coalesce(p_action,'')));
  if act not in ('send','sign','decline','archive') then return query select false,'Действие: send/sign/decline/archive'; return; end if;
  select * into d from public.app_hr_docs where id = p_id and (public.app_is_platform_admin(p_token) or tenant_id = ten);
  if d.id is null then return query select false,'Документ не найден'; return; end if;
  -- подписать/ознакомиться может сам сотрудник или admin/owner
  if act in ('sign','decline') and not (public.app_is_platform_admin(p_token) or public.app_is_owner(p_token) or d.employee_login = uname) then
    return query select false,'Подпись доступна сотруднику, которому адресован документ'; return;
  end if;
  if act = 'send' then
    update public.app_hr_docs set status='sent', updated_at=now() where id = p_id;
    select u.id into au from public.app_users u where u.login = d.employee_login and u.tenant_id = ten limit 1;
    if au is not null then perform public.app_notif_send(au, 'Кадровый документ на ознакомление', d.title, 'apps/kedo/index.html'); end if;
    return query select true,'Документ отправлен сотруднику';
  elsif act = 'sign' then
    update public.app_hr_docs set status='signed', signed_at=now(), signed_by=uid, sign_method='ПЭП', comment=nullif(trim(p_comment),''), updated_at=now() where id = p_id;
    return query select true,'Документ подписан (ПЭП)';
  elsif act = 'decline' then
    update public.app_hr_docs set status='declined', comment=nullif(trim(p_comment),''), updated_at=now() where id = p_id;
    return query select true,'Документ отклонён';
  else
    update public.app_hr_docs set status='archived', updated_at=now() where id = p_id;
    return query select true,'Документ в архив';
  end if;
end $$;

create or replace function public.app_hr_doc_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  delete from public.app_hr_docs d where d.id = p_id and d.status in ('draft','declined') and (public.app_is_platform_admin(p_token) or d.tenant_id = ten);
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Документ не найден или уже отправлен'; return; end if;
  return query select true,'Документ удалён';
end $$;

-- Личный кабинет сотрудника
create or replace function public.app_hr_my_docs(p_token uuid)
returns table (id uuid, doc_type text, title text, status text, signed_at timestamptz, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; ulogin text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.ulogin into ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select d.id, d.doc_type, d.title, d.status, d.signed_at, d.created_at
    from public.app_hr_docs d where d.tenant_id = ten and d.employee_login = ulogin order by d.created_at desc;
end $$;

-- ---------- RPC: шаблоны ----------
create or replace function public.app_hr_templates_list(p_token uuid)
returns table (id uuid, code text, name text, doc_type text, body text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select t.id, t.code, t.name, t.doc_type, t.body from public.app_hr_doc_templates t where adm or t.tenant_id = ten order by t.name;
end $$;

create or replace function public.app_hr_template_save(p_token uuid, p_id uuid, p_code text, p_name text, p_doc_type text, p_body text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if coalesce(trim(p_name),'') = '' then return query select false,'Укажите название шаблона', null::uuid; return; end if;
  if p_id is null then
    insert into public.app_hr_doc_templates (tenant_id, code, name, doc_type, body)
    values (ten, nullif(trim(p_code),''), left(trim(p_name),160), nullif(trim(p_doc_type),''), p_body)
    returning app_hr_doc_templates.id into newid;
    return query select true,'Шаблон создан', newid;
  else
    update public.app_hr_doc_templates t set code = nullif(trim(p_code),''), name = left(trim(p_name),160), doc_type = nullif(trim(p_doc_type),''), body = p_body
     where t.id = p_id and (public.app_is_platform_admin(p_token) or t.tenant_id = ten)
     returning t.id into newid;
    if newid is null then return query select false,'Шаблон не найден', null::uuid; return; end if;
    return query select true,'Шаблон сохранён', newid;
  end if;
end $$;

-- ---------- RPC: МЧД ----------
create or replace function public.app_mchd_list(p_token uuid)
returns table (id uuid, number text, issued_to_login text, authority text, valid_from date, valid_to date, status text, note text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select m.id, m.number, m.issued_to_login, m.authority, m.valid_from, m.valid_to, m.status, m.note
    from public.app_mchd m where adm or m.tenant_id = ten order by m.created_at desc;
end $$;

create or replace function public.app_mchd_save(p_token uuid, p_id uuid, p_number text, p_to text, p_authority text, p_from date, p_to_date date, p_status text, p_note text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; newid uuid; st text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if coalesce(trim(p_to),'') = '' then return query select false,'Укажите доверенное лицо', null::uuid; return; end if;
  st := coalesce(nullif(trim(p_status),''),'active');
  if st not in ('active','revoked','expired') then return query select false,'Недопустимый статус', null::uuid; return; end if;
  if p_id is null then
    insert into public.app_mchd (tenant_id, number, issued_to_login, authority, valid_from, valid_to, status, note)
    values (ten, nullif(trim(p_number),''), trim(p_to), nullif(trim(p_authority),''), p_from, p_to_date, st, nullif(trim(p_note),''))
    returning app_mchd.id into newid;
    return query select true,'МЧД создана', newid;
  else
    update public.app_mchd m set number = nullif(trim(p_number),''), issued_to_login = trim(p_to), authority = nullif(trim(p_authority),''),
           valid_from = p_from, valid_to = p_to_date, status = st, note = nullif(trim(p_note),'')
     where m.id = p_id and (public.app_is_platform_admin(p_token) or m.tenant_id = ten)
     returning m.id into newid;
    if newid is null then return query select false,'МЧД не найдена', null::uuid; return; end if;
    return query select true,'МЧД сохранена', newid;
  end if;
end $$;

create or replace function public.app_mchd_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; st text; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  st := lower(trim(coalesce(p_status,'')));
  if st not in ('active','revoked','expired') then return query select false,'Недопустимый статус'; return; end if;
  update public.app_mchd m set status = st where m.id = p_id and (public.app_is_platform_admin(p_token) or m.tenant_id = ten);
  get diagnostics n = row_count;
  if n = 0 then return query select false,'МЧД не найдена'; return; end if;
  return query select true,'Статус МЧД: ' || st;
end $$;

create or replace function public.app_kedo_kpi(p_token uuid)
returns table (total bigint, draft bigint, sent bigint, signed bigint, mchd_active bigint, templates bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select
    (select count(*) from public.app_hr_docs d where adm or d.tenant_id=ten),
    (select count(*) from public.app_hr_docs d where (adm or d.tenant_id=ten) and d.status='draft'),
    (select count(*) from public.app_hr_docs d where (adm or d.tenant_id=ten) and d.status='sent'),
    (select count(*) from public.app_hr_docs d where (adm or d.tenant_id=ten) and d.status='signed'),
    (select count(*) from public.app_mchd m where (adm or m.tenant_id=ten) and m.status='active'),
    (select count(*) from public.app_hr_doc_templates t where adm or t.tenant_id=ten);
end $$;

-- ================= Демо =================
insert into public.app_hr_doc_templates (tenant_id, code, name, doc_type, body)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'vacation', 'Заявление на отпуск', 'vacation', 'Прошу предоставить отпуск с {{from}} по {{to}} ({дней} дней).'
where not exists (select 1 from public.app_hr_doc_templates where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and code='vacation');

insert into public.app_hr_docs (tenant_id, employee_login, doc_type, title, number, status, payload, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'manager', 'ack', 'Ознакомление с приказом №1', 'КЭДО-0001', 'sent', '{"order":"№1"}'::jsonb, 'owner'
where not exists (select 1 from public.app_hr_docs where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and number='КЭДО-0001');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags, section)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'Платформа', 'КЭДО: кадровый ЭДО, шаблоны, личный кабинет, МЧД',
       'W20: кадровые документы (app_hr_docs: приём/перевод/увольнение/отпуск/больничный/ознакомление/приказ; статусы draft→sent→signed/declined→archived; подписание ПЭП — задел под УНЭП/УКЭП/Госключ), шаблоны (app_hr_doc_templates), личный кабинет сотрудника (app_hr_my_docs — ознакомление/подпись), МЧД (app_mchd), KPI (app_kedo_kpi). Модуль «Кадры (КЭДО)» (apps/kedo).',
       'КЭДО кадры электронный документооборот приказ заявление ознакомление подпись МЧД', 'Совместная работа'
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and question = 'КЭДО: кадровый ЭДО, шаблоны, личный кабинет, МЧД'
);

-- ---------- Права ----------
grant execute on function public.app_hr_docs_list(uuid,text,text,text) to anon, authenticated;
grant execute on function public.app_hr_doc_save(uuid,uuid,text,text,text,jsonb) to anon, authenticated;
grant execute on function public.app_hr_doc_sign(uuid,uuid,text,text) to anon, authenticated;
grant execute on function public.app_hr_doc_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_hr_my_docs(uuid) to anon, authenticated;
grant execute on function public.app_hr_templates_list(uuid) to anon, authenticated;
grant execute on function public.app_hr_template_save(uuid,uuid,text,text,text,text) to anon, authenticated;
grant execute on function public.app_mchd_list(uuid) to anon, authenticated;
grant execute on function public.app_mchd_save(uuid,uuid,text,text,text,date,date,text,text) to anon, authenticated;
grant execute on function public.app_mchd_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_kedo_kpi(uuid) to anon, authenticated;
