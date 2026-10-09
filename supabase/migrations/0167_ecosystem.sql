-- ============================================================
-- 3DMP Service · 0167_ecosystem.sql  (W17 — Экосистема/интеграции)
-- Дополнение к уже существующим app_api_keys/app_webhooks: лог вызовов API,
-- реестр подписей (ПЭП/УНЭП/УКЭП/Госключ), проверка контрагентов, KPI экосистемы.
-- 1С/МДМ и PLM — через app_integrations и app_mdm_links (ранее).
-- Идемпотентно. Зависит от 0001..0166.
-- ============================================================

create table if not exists public.app_api_log (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  key_id     uuid references public.app_api_keys (id) on delete set null,
  method     text,
  path       text,
  status     integer,
  ts         timestamptz not null default now()
);
create index if not exists app_api_log_idx on public.app_api_log (tenant_id, ts desc);
alter table public.app_api_log enable row level security;

create table if not exists public.app_signatures (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  entity_type   text not null,
  entity_id     uuid,
  signer_login  text,
  method        text not null default 'ПЭП',   -- ПЭП|УНЭП|УКЭП|Госключ
  status        text not null default 'signed',-- signed|revoked
  signed_at     timestamptz not null default now(),
  note          text
);
create index if not exists app_signatures_idx on public.app_signatures (tenant_id, entity_type, entity_id);
alter table public.app_signatures enable row level security;

create table if not exists public.app_counterparty_checks (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid references public.tenants (id),
  entity_type  text not null default 'customer',  -- customer|supplier
  entity_id    uuid,
  entity_name  text,
  inn          text,
  risk_score   integer not null default 0,
  risk_level   text not null default 'low',        -- low|medium|high
  source       text default 'heuristic',
  note         text,
  checked_at   timestamptz not null default now()
);
create index if not exists app_cp_checks_idx on public.app_counterparty_checks (tenant_id, entity_id);
alter table public.app_counterparty_checks enable row level security;

-- ---------- Лог вызовов API ----------
create or replace function public.app_api_log_list(p_token uuid, p_limit integer default 100)
returns table (method text, path text, status integer, key_name text, ts timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select l.method, l.path, l.status, k.name, l.ts
    from public.app_api_log l left join public.app_api_keys k on k.id = l.key_id
   where adm or l.tenant_id = ten order by l.ts desc limit greatest(coalesce(p_limit,100),1);
end $$;

create or replace function public.app_api_log_write(p_key text, p_method text, p_path text, p_status integer)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare rec record;
begin
  select k.id, k.tenant_id into rec from public.app_api_keys k where k.api_key::text = coalesce(p_key,'') and k.active limit 1;
  insert into public.app_api_log (tenant_id, key_id, method, path, status)
  values (rec.tenant_id, rec.id, left(coalesce(p_method,''),10), left(coalesce(p_path,''),200), p_status);
  if rec.id is not null then update public.app_api_keys set last_used_at = now() where id = rec.id; end if;
  return query select true, 'Записано';
end $$;

-- ---------- Подписи ----------
create or replace function public.app_signatures_list(p_token uuid, p_entity_type text default null, p_entity_id uuid default null)
returns table (id uuid, entity_type text, entity_id uuid, signer_login text, method text, status text, signed_at timestamptz, note text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select s.id, s.entity_type, s.entity_id, s.signer_login, s.method, s.status, s.signed_at, s.note
    from public.app_signatures s
   where (adm or s.tenant_id = ten)
     and (p_entity_type is null or p_entity_type='' or s.entity_type = p_entity_type)
     and (p_entity_id is null or s.entity_id = p_entity_id)
   order by s.signed_at desc;
end $$;

create or replace function public.app_signature_register(p_token uuid, p_entity_type text, p_entity_id uuid, p_method text, p_note text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; newid uuid; m text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if coalesce(trim(p_entity_type),'') = '' then return query select false,'Укажите тип объекта', null::uuid; return; end if;
  m := coalesce(nullif(trim(p_method),''),'ПЭП');
  if m not in ('ПЭП','УНЭП','УКЭП','Госключ') then return query select false,'Метод: ПЭП/УНЭП/УКЭП/Госключ', null::uuid; return; end if;
  insert into public.app_signatures (tenant_id, entity_type, entity_id, signer_login, method, status, note)
  values (ten, lower(trim(p_entity_type)), p_entity_id, uname, m, 'signed', nullif(trim(p_note),''))
  returning app_signatures.id into newid;
  return query select true,'Подпись зарегистрирована (' || m || ')', newid;
end $$;

create or replace function public.app_signature_revoke(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  update public.app_signatures s set status='revoked' where s.id = p_id and (public.app_is_platform_admin(p_token) or s.tenant_id = ten);
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Подпись не найдена'; return; end if;
  return query select true,'Подпись отозвана';
end $$;

-- ---------- Проверка контрагентов ----------
create or replace function public.app_counterparty_check(p_token uuid, p_entity_type text, p_entity_id uuid, p_name text, p_inn text)
returns table (ok boolean, message text, risk_score integer, risk_level text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; sc integer := 0; lvl text; inn text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',0,null::text; return; end if;
  ten := public.app_my_tenant(p_token);
  inn := trim(coalesce(p_inn,''));
  if inn = '' then sc := sc + 25; elsif length(inn) not in (10,12) then sc := sc + 40; end if;
  if coalesce(trim(p_name),'') = '' then sc := sc + 25; end if;
  lvl := case when sc >= 60 then 'high' when sc >= 30 then 'medium' else 'low' end;
  insert into public.app_counterparty_checks (tenant_id, entity_type, entity_id, entity_name, inn, risk_score, risk_level, source)
  values (ten, coalesce(nullif(trim(p_entity_type),''),'customer'), p_entity_id, left(trim(p_name),200), nullif(inn,''), sc, lvl, 'heuristic');
  return query select true, 'Риск: ' || lvl || ' (' || sc || ')', sc, lvl;
end $$;

create or replace function public.app_counterparty_checks_list(p_token uuid, p_limit integer default 50)
returns table (id uuid, entity_type text, entity_name text, inn text, risk_score integer, risk_level text, checked_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select c.id, c.entity_type, c.entity_name, c.inn, c.risk_score, c.risk_level, c.checked_at
    from public.app_counterparty_checks c where adm or c.tenant_id = ten order by c.checked_at desc limit greatest(coalesce(p_limit,50),1);
end $$;

create or replace function public.app_ecosystem_kpi(p_token uuid)
returns table (api_keys bigint, keys_active bigint, webhooks bigint, signatures bigint, cp_high bigint, api_calls bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select
    (select count(*) from public.app_api_keys k where adm or k.tenant_id=ten),
    (select count(*) from public.app_api_keys k where (adm or k.tenant_id=ten) and k.active),
    (select count(*) from public.app_webhooks w where adm or w.tenant_id=ten),
    (select count(*) from public.app_signatures s where adm or s.tenant_id=ten),
    (select count(*) from public.app_counterparty_checks c where (adm or c.tenant_id=ten) and c.risk_level='high'),
    (select count(*) from public.app_api_log l where adm or l.tenant_id=ten);
end $$;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags, section)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'Платформа', 'Экосистема: API, подписи, проверка контрагентов',
       'W17: публичный REST API — ключи (app_api_keys + app_api_key_create/list/revoke — реализовано ранее) и лог вызовов (app_api_log, app_api_log_list/write, KPI); webhooks (app_webhooks + app_webhook_add/list/toggle/delete — ранее); реестр подписей (app_signatures: ПЭП/УНЭП/УКЭП/Госключ; app_signature_register/revoke/list); проверка контрагентов (app_counterparty_check: скоринг риска по ИНН/названию — задел под внешний сервис; список app_counterparty_checks_list); KPI (app_ecosystem_kpi). Обмен с 1С/PLM — через app_integrations и app_mdm_links.',
       'экосистема API ключи webhooks подписи контрагенты риск 1С PLM', 'Платформа'
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Экосистема: API, подписи, проверка контрагентов');

-- ---------- Права ----------
grant execute on function public.app_api_log_list(uuid,integer) to anon, authenticated;
grant execute on function public.app_api_log_write(text,text,text,integer) to anon, authenticated;
grant execute on function public.app_signatures_list(uuid,text,uuid) to anon, authenticated;
grant execute on function public.app_signature_register(uuid,text,uuid,text,text) to anon, authenticated;
grant execute on function public.app_signature_revoke(uuid,uuid) to anon, authenticated;
grant execute on function public.app_counterparty_check(uuid,text,uuid,text,text) to anon, authenticated;
grant execute on function public.app_counterparty_checks_list(uuid,integer) to anon, authenticated;
grant execute on function public.app_ecosystem_kpi(uuid) to anon, authenticated;
