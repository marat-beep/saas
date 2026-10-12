-- ============================================================
-- 3DMP Service · 0191_docs2.sql  (X8 — Документы 2.0)
-- Версии шаблонов (app_template_versions), печатные шаблоны (app_doc_print_templates),
-- вычисляемые формулы (app_doc_formula_eval), экспорт документа в ЭДО (app_doc_to_edo).
-- Идемпотентно. Зависит от 0001..0190.
-- ============================================================

create table if not exists public.app_template_versions (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  template_id   uuid references public.app_doc_templates (id) on delete cascade,
  version       integer not null default 1,
  name          text,
  doc_type      text,
  body          text,
  note          text,
  created_login text,
  created_at    timestamptz not null default now()
);
create index if not exists app_template_versions_idx on public.app_template_versions (template_id, version desc);
alter table public.app_template_versions enable row level security;

create table if not exists public.app_doc_print_templates (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  code          text,
  name          text not null,
  doc_type      text,
  body          text,
  created_login text,
  created_at    timestamptz not null default now()
);
create index if not exists app_doc_print_templates_idx on public.app_doc_print_templates (tenant_id, doc_type);
alter table public.app_doc_print_templates enable row level security;

-- ================= RPC: версии шаблонов =================
create or replace function public.app_template_versions_list(p_token uuid, p_template_id uuid)
returns table (id uuid, version integer, name text, doc_type text, body text, note text, created_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select v.id, v.version, v.name, v.doc_type, v.body, v.note, v.created_login, v.created_at
      from public.app_template_versions v
     where v.template_id = p_template_id and (adm or v.tenant_id = ten)
     order by v.version desc;
end $$;

create or replace function public.app_template_version_save(p_token uuid, p_template_id uuid, p_note text)
returns table (ok boolean, message text, version integer)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; t record; vnum integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::integer; return; end if;
  if not public.app_can_edit(p_token, 'templates') then return query select false,'Нет прав на шаблоны', null::integer; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  select * into t from public.app_doc_templates where id = p_template_id and (public.app_is_platform_admin(p_token) or tenant_id = ten);
  if t.id is null then return query select false,'Шаблон не найден', null::integer; return; end if;
  select coalesce(max(version),0) + 1 into vnum from public.app_template_versions where template_id = p_template_id;
  insert into public.app_template_versions (tenant_id, template_id, version, name, doc_type, body, note, created_login)
  values (ten, p_template_id, vnum, t.name, t.doc_type, t.body, nullif(trim(p_note),''), uname);
  return query select true,'Версия ' || vnum || ' сохранена', vnum;
end $$;

-- ================= RPC: печатные шаблоны =================
create or replace function public.app_doc_print_templates_list(p_token uuid, p_doc_type text default null)
returns table (id uuid, code text, name text, doc_type text, body text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select p.id, p.code, p.name, p.doc_type, p.body
      from public.app_doc_print_templates p
     where (adm or p.tenant_id = ten) and (p_doc_type is null or p_doc_type = '' or p.doc_type = p_doc_type)
     order by p.name;
end $$;

create or replace function public.app_doc_print_template_save(p_token uuid, p_id uuid, p_code text, p_name text, p_doc_type text, p_body text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  if not public.app_can_edit(p_token, 'docs') then return query select false,'Нет прав на документы', null::uuid; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if coalesce(trim(p_name),'') = '' then return query select false,'Укажите название шаблона', null::uuid; return; end if;
  if p_id is null then
    insert into public.app_doc_print_templates (tenant_id, code, name, doc_type, body, created_login)
    values (ten, nullif(trim(p_code),''), left(trim(p_name),160), nullif(trim(p_doc_type),''), p_body, uname)
    returning app_doc_print_templates.id into newid;
    return query select true,'Печатный шаблон создан', newid;
  else
    update public.app_doc_print_templates p set code = nullif(trim(p_code),''), name = left(trim(p_name),160),
           doc_type = nullif(trim(p_doc_type),''), body = p_body
     where p.id = p_id and (public.app_is_platform_admin(p_token) or p.tenant_id = ten)
     returning p.id into newid;
    if newid is null then return query select false,'Шаблон не найден', null::uuid; return; end if;
    return query select true,'Печатный шаблон сохранён', newid;
  end if;
end $$;

-- ================= RPC: вычисляемые формулы =================
-- Подстановка {переменных} из p_values (jsonb) и вычисление арифметики (+, -, *, /, скобки).
create or replace function public.app_doc_formula_eval(p_token uuid, p_expr text, p_values jsonb)
returns table (ok boolean, result numeric, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; k text; v text; expr text; safe text; res numeric;
begin
  if not public.app_production_allowed(p_token) then return query select false, null::numeric,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  expr := coalesce(p_expr,'');
  if coalesce(trim(expr),'') = '' then return query select false, null::numeric,'Пустая формула'; return; end if;
  for k, v in select key, value from jsonb_each_text(coalesce(p_values,'{}'::jsonb)) loop
    expr := replace(expr, '{' || k || '}', regexp_replace(coalesce(v,'0'), '[^0-9.\-]', '', 'g'));
  end loop;
  safe := regexp_replace(expr, '[^0-9+\-*/(). ]', '', 'g');
  if coalesce(trim(safe),'') = '' then return query select false, null::numeric,'Некорректная формула'; return; end if;
  begin
    execute 'select (' || safe || ')::numeric' into res;
  exception when others then
    return query select false, null::numeric,'Ошибка вычисления'; return;
  end;
  return query select true, res, 'Результат: ' || res::text;
end $$;

-- ================= RPC: экспорт документа в ЭДО =================
create or replace function public.app_doc_to_edo(p_token uuid, p_doc_id uuid)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; d record; newid uuid; num text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  if not public.app_can_edit(p_token, 'edo') then return query select false,'Нет прав на ЭДО', null::uuid; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  select * into d from public.app_documents where id = p_doc_id and (public.app_is_platform_admin(p_token) or tenant_id = ten);
  if d.id is null then return query select false,'Документ не найден', null::uuid; return; end if;
  if exists (select 1 from public.app_doc_links l where l.entity_type = 'document' and l.entity_id = p_doc_id) then
    return query select false,'Документ уже зарегистрирован в ЭДО', null::uuid; return;
  end if;
  num := 'ЭДО-' || to_char(current_date,'YYYY') || '-' || lpad(nextval('public.app_doc_seq')::text, 5, '0');
  insert into public.app_doc_flows (tenant_id, kind, doc_type, title, correspondent, summary, status, responsible_login, reg_number, reg_date, created_login)
  values (ten, 'out', d.doc_type, left(d.number || ' ' || d.title, 200), d.counterparty, left(coalesce(d.content,''),500), 'registered', uname, num, current_date, uname)
  returning app_doc_flows.id into newid;
  insert into public.app_doc_links (tenant_id, doc_id, entity_type, entity_id, note)
  values (ten, newid, 'document', p_doc_id, 'Экспорт из реестра документов');
  return query select true,'Документ передан в ЭДО: ' || num, newid;
end $$;

-- ================= Демо =================
insert into public.app_doc_print_templates (tenant_id, code, name, doc_type, body, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'kp_print', 'Печать КП', 'kp',
       'Коммерческое предложение № {number} от {date}' || chr(10) || 'Заказчик: {customer}' || chr(10) || 'Сумма: {amount} ₽', 'owner'
where not exists (select 1 from public.app_doc_print_templates where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and code='kp_print');

-- ================= База знаний =================
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Продажи','Документы 2.0: версии шаблонов, печатные шаблоны, формулы, экспорт в ЭДО (X8)',
   'Документы 2.0: версии шаблонов (app_template_versions + app_template_version_save/list — снимок шаблона на каждую правку), печатные шаблоны (app_doc_print_templates + app_doc_print_templates_list/save — подстановки {number}/{date}/{customer}/{amount}), вычисляемые формулы (app_doc_formula_eval — подстановка {переменных} из jsonb и арифметика +,-,*,/), экспорт готового документа в ЭДО (app_doc_to_edo — создаёт запись в app_doc_flows с номером ЭДО-ГГГГ-NNNNN и связью). Единый контур: docs ↔ templates ↔ docbuilder ↔ edo/kedo.',
   'документы версии шаблон печать формула экспорт ЭДО подстановки')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001'
     and question = 'Документы 2.0: версии шаблонов, печатные шаблоны, формулы, экспорт в ЭДО (X8)'
);

-- ================= Права =================
grant execute on function public.app_template_versions_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_template_version_save(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_doc_print_templates_list(uuid,text) to anon, authenticated;
grant execute on function public.app_doc_print_template_save(uuid,uuid,text,text,text,text) to anon, authenticated;
grant execute on function public.app_doc_formula_eval(uuid,text,jsonb) to anon, authenticated;
grant execute on function public.app_doc_to_edo(uuid,uuid) to anon, authenticated;
