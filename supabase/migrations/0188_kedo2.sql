-- ============================================================
-- 3DMP Service · 0188_kedo2.sql  (X4 — КЭДО 2.0)
-- Массовые ознакомления (app_hr_bulk/_items), маршруты кадровых документов
-- (reuse движка согласований W10: app_approval_routes/requests/actions),
-- провайдер ЭП (signature_provider + app_hr_sign_ext через app_integrations),
-- дашборд КЭДО. Идемпотентно. Зависит от 0001..0187.
-- ============================================================

alter table public.app_hr_docs add column if not exists signature_provider text;
alter table public.app_hr_docs add column if not exists route_request_id uuid;

create table if not exists public.app_hr_bulk (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  title         text not null,
  doc_type      text not null default 'ack',
  body          text,
  status        text not null default 'active',   -- active|closed
  created_login text,
  created_at    timestamptz not null default now()
);
create index if not exists app_hr_bulk_idx on public.app_hr_bulk (tenant_id, created_at desc);
alter table public.app_hr_bulk enable row level security;

create table if not exists public.app_hr_bulk_items (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid references public.tenants (id),
  bulk_id        uuid not null references public.app_hr_bulk (id) on delete cascade,
  employee_login text not null,
  doc_id         uuid references public.app_hr_docs (id) on delete set null,
  created_at     timestamptz not null default now()
);
create index if not exists app_hr_bulk_items_idx on public.app_hr_bulk_items (bulk_id);
alter table public.app_hr_bulk_items enable row level security;

create sequence if not exists public.app_hr_bulk_doc_seq;

-- ================= RPC: массовые ознакомления =================
create or replace function public.app_hr_bulk_list(p_token uuid)
returns table (id uuid, title text, doc_type text, total bigint, signed bigint, status text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select b.id, b.title, b.doc_type,
           (select count(*) from public.app_hr_bulk_items i where i.bulk_id = b.id),
           (select count(*) from public.app_hr_bulk_items i join public.app_hr_docs d on d.id = i.doc_id
             where i.bulk_id = b.id and d.status = 'signed'),
           b.status, b.created_at
      from public.app_hr_bulk b
     where adm or b.tenant_id = ten
     order by b.created_at desc;
end $$;

create or replace function public.app_hr_bulk_create(p_token uuid, p_title text, p_doc_type text, p_body text, p_employees jsonb)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; newid uuid; lg text; did uuid; cnt integer := 0; tp text; ttl text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  if not public.app_can_edit(p_token, 'kedo') then return query select false,'Нет прав на КЭДО', null::uuid; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if coalesce(trim(p_title),'') = '' then return query select false,'Укажите название ознакомления', null::uuid; return; end if;
  if p_employees is null or jsonb_typeof(p_employees) <> 'array' or jsonb_array_length(p_employees) = 0 then
    return query select false,'Укажите список сотрудников', null::uuid; return;
  end if;
  tp := coalesce(nullif(trim(p_doc_type),''),'ack');
  insert into public.app_hr_bulk (tenant_id, title, doc_type, body, created_login)
  values (ten, left(trim(p_title),200), tp, nullif(trim(p_body),''), uname)
  returning app_hr_bulk.id into newid;
  for lg in select trim(value) from jsonb_array_elements_text(p_employees) as t(value) loop
    if coalesce(lg,'') = '' then continue; end if;
    ttl := left(trim(p_title),200);
    insert into public.app_hr_docs (tenant_id, employee_login, doc_type, title, number, status, payload, created_login)
    values (ten, lg, tp, ttl, 'ОЗН-' || lpad(nextval('public.app_hr_bulk_doc_seq')::text, 5, '0'), 'sent',
            jsonb_build_object('bulk_id', newid, 'text', coalesce(p_body,'')), uname)
    returning app_hr_docs.id into did;
    insert into public.app_hr_bulk_items (tenant_id, bulk_id, employee_login, doc_id) values (ten, newid, lg, did);
    cnt := cnt + 1;
  end loop;
  return query select true, 'Создано ознакомлений: ' || cnt, newid;
end $$;

create or replace function public.app_hr_bulk_items(p_token uuid, p_bulk_id uuid)
returns table (employee_login text, doc_id uuid, status text, signed_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select i.employee_login, i.doc_id, coalesce(d.status,'—'), d.signed_at
      from public.app_hr_bulk_items i
      left join public.app_hr_docs d on d.id = i.doc_id
      join public.app_hr_bulk b on b.id = i.bulk_id
     where i.bulk_id = p_bulk_id and (adm or b.tenant_id = ten)
     order by i.employee_login;
end $$;

create or replace function public.app_hr_bulk_scan(p_token uuid)
returns table (notified integer, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; rec record; cnt integer := 0;
begin
  if not public.app_production_allowed(p_token) then return query select 0,'Доступ запрещён'; return; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  for rec in
    select b.title, count(*) as pend
      from public.app_hr_bulk b
      join public.app_hr_bulk_items i on i.bulk_id = b.id
      left join public.app_hr_docs d on d.id = i.doc_id
     where (adm or b.tenant_id = ten) and b.status = 'active' and coalesce(d.status,'') <> 'signed'
     group by b.id, b.title
  loop
    perform public.app_notif_roles_t(ten, array['admin','owner','manager','hr'],
      'КЭДО: не ознакомлены', '«' || rec.title || '» — ожидают подписи: ' || rec.pend, 'apps/kedo/index.html');
    cnt := cnt + 1;
  end loop;
  return query select cnt, 'Ознакомлений под контролем: ' || cnt;
end $$;

-- ================= RPC: маршруты кадровых документов (reuse W10) =================
create or replace function public.app_hr_routes_list(p_token uuid)
returns table (id uuid, name text, doc_type text, steps jsonb, active boolean)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select r.id, r.name, r.doc_type, r.steps, r.active
      from public.app_approval_routes r
     where (adm or r.tenant_id = ten) and r.doc_type = 'hr_doc'
     order by r.created_at desc;
end $$;

create or replace function public.app_hr_route_save(p_token uuid, p_id uuid, p_name text, p_steps jsonb, p_active boolean)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare r record;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  if not public.app_can_edit(p_token, 'kedo') then return query select false,'Нет прав на КЭДО', null::uuid; return; end if;
  select * into r from public.app_approval_route_save(p_token, p_id, p_name, 'hr_doc', p_steps, p_active) x;
  return query select r.ok, r.message, r.id;
end $$;

create or replace function public.app_hr_route_start(p_token uuid, p_doc_id uuid, p_route_id uuid)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; d record; r record;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  if not public.app_can_edit(p_token, 'kedo') then return query select false,'Нет прав на КЭДО', null::uuid; return; end if;
  ten := public.app_my_tenant(p_token);
  select * into d from public.app_hr_docs where id = p_doc_id and (public.app_is_platform_admin(p_token) or tenant_id = ten);
  if d.id is null then return query select false,'Документ не найден', null::uuid; return; end if;
  select * into r from public.app_approval_request_create(p_token, p_route_id, 'hr_doc', p_doc_id, d.title) x;
  if not r.ok then return query select false, r.message, null::uuid; return; end if;
  update public.app_hr_docs set route_request_id = r.id, updated_at = now() where id = p_doc_id;
  return query select true, 'Документ запущен по маршруту', r.id;
end $$;

create or replace function public.app_hr_route_act(p_token uuid, p_request_id uuid, p_action text, p_comment text)
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
  if req.entity_type = 'hr_doc' and req.entity_id is not null then
    if r.message like '%согласован%' and r.message not like '%передан%' then
      update public.app_hr_docs set status='signed', signed_at=now(), sign_method=coalesce(sign_method,'Маршрут'), updated_at=now() where id = req.entity_id;
    elsif r.message like '%отклонена%' then
      update public.app_hr_docs set status='declined', updated_at=now() where id = req.entity_id;
    end if;
  end if;
  return query select true, r.message;
end $$;

-- ================= RPC: подпись внешним провайдером ЭП =================
create or replace function public.app_hr_sign_ext(p_token uuid, p_doc_id uuid, p_provider text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; prov text; iid uuid; d record;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  if not public.app_can_edit(p_token, 'kedo') then return query select false,'Нет прав на КЭДО'; return; end if;
  ten := public.app_my_tenant(p_token);
  prov := lower(trim(coalesce(p_provider,'ukep')));
  select * into d from public.app_hr_docs where id = p_doc_id and (public.app_is_platform_admin(p_token) or tenant_id = ten);
  if d.id is null then return query select false,'Документ не найден'; return; end if;
  select i.id into iid from public.app_integrations i
   where i.tenant_id = ten and coalesce(i.active,true) and i.kind in (prov, 'edo', 'esign', 'webhook')
   order by i.created_at limit 1;
  if iid is null then
    return query select false, 'Нет активной интеграции провайдера ЭП («' || prov || '») — настройте в «Интеграции»';
    return;
  end if;
  perform public.app_integration_enqueue(p_token, iid, 'out', jsonb_build_object(
    'kind', 'esign', 'provider', prov, 'doc_id', p_doc_id, 'number', d.number,
    'employee', d.employee_login, 'title', d.title));
  update public.app_hr_docs set signature_provider = prov, sign_method = prov, updated_at = now() where id = p_doc_id;
  return query select true, 'Документ отправлен провайдеру ЭП (' || prov || ')';
end $$;

create or replace function public.app_kedo_dashboard(p_token uuid)
returns table (total bigint, draft bigint, sent bigint, signed bigint, declined bigint, mchd_active bigint,
               templates bigint, bulks bigint, bulk_pending bigint, routes_active bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select
    (select count(*) from public.app_hr_docs d where adm or d.tenant_id=ten),
    (select count(*) from public.app_hr_docs d where (adm or d.tenant_id=ten) and d.status='draft'),
    (select count(*) from public.app_hr_docs d where (adm or d.tenant_id=ten) and d.status='sent'),
    (select count(*) from public.app_hr_docs d where (adm or d.tenant_id=ten) and d.status='signed'),
    (select count(*) from public.app_hr_docs d where (adm or d.tenant_id=ten) and d.status='declined'),
    (select count(*) from public.app_mchd m where (adm or m.tenant_id=ten) and m.status='active'),
    (select count(*) from public.app_hr_doc_templates t where adm or t.tenant_id=ten),
    (select count(*) from public.app_hr_bulk b where adm or b.tenant_id=ten),
    (select count(*) from public.app_hr_bulk_items i join public.app_hr_docs d on d.id = i.doc_id
      where (adm or i.tenant_id=ten) and coalesce(d.status,'') <> 'signed'),
    (select count(*) from public.app_approval_routes r where (adm or r.tenant_id=ten) and r.doc_type='hr_doc' and coalesce(r.active,true));
end $$;

-- ================= Демо =================
insert into public.app_approval_routes (tenant_id, name, doc_type, steps, active, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'Кадровый приказ: руководитель → директор', 'hr_doc',
       '[{"ord":1,"role":"manager","name":"Кадры"},{"ord":2,"role":"director","name":"Директор"}]'::jsonb, true, 'owner'
where not exists (select 1 from public.app_approval_routes where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and doc_type='hr_doc');

-- ================= База знаний =================
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','КЭДО 2.0: массовые ознакомления, маршруты, провайдер ЭП (X4)',
   'КЭДО 2.0: массовые ознакомления (app_hr_bulk + app_hr_bulk_items — по списку сотрудников создаются кадровые документы и отслеживается подпись каждого), маршруты кадровых документов (app_hr_routes_list/route_save/route_start/route_act — переиспользован движок согласований W10: app_approval_routes/requests/actions; при финальном согласовании документ переходит в signed), подпись внешним провайдером ЭП (app_hr_sign_ext — документ ставится в очередь app_integrations для УКЭП/Госключ; поле app_hr_docs.signature_provider). Дашборд app_kedo_dashboard. RPC: app_hr_bulk_list/create/items/scan, app_hr_routes_list, app_hr_route_save/start/act, app_hr_sign_ext, app_kedo_dashboard.',
   'КЭДО массовое ознакомление маршрут согласование подпись УКЭП Госключ провайдер ЭП')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001'
     and question = 'КЭДО 2.0: массовые ознакомления, маршруты, провайдер ЭП (X4)'
);

-- ================= Права =================
grant execute on function public.app_hr_bulk_list(uuid) to anon, authenticated;
grant execute on function public.app_hr_bulk_create(uuid,text,text,text,jsonb) to anon, authenticated;
grant execute on function public.app_hr_bulk_items(uuid,uuid) to anon, authenticated;
grant execute on function public.app_hr_bulk_scan(uuid) to anon, authenticated;
grant execute on function public.app_hr_routes_list(uuid) to anon, authenticated;
grant execute on function public.app_hr_route_save(uuid,uuid,text,jsonb,boolean) to anon, authenticated;
grant execute on function public.app_hr_route_start(uuid,uuid,uuid) to anon, authenticated;
grant execute on function public.app_hr_route_act(uuid,uuid,text,text) to anon, authenticated;
grant execute on function public.app_hr_sign_ext(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_kedo_dashboard(uuid) to anon, authenticated;
