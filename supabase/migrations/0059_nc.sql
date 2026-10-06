-- ============================================================
-- 3DMP Service · 0059_nc.sql  (v37 — ЭПИК B: реестр УП / прототипы B18/B27)
-- Управляющие программы: заказ, деталь, станок, номер, версия, время, статус, файлы.
-- Расширен список типов вложений (nc и др.). База знаний. Зависит от 0001..0058.
-- ============================================================

create table if not exists public.app_nc_programs (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  order_id      uuid references public.app_orders (id) on delete set null,
  equipment_id  uuid references public.app_equipment (id) on delete set null,
  detail        text not null,
  program_no    text,
  version       integer not null default 1,
  program_time_min numeric,
  status        text not null default 'draft', -- draft|approved|archive
  note          text,
  created_login text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists app_nc_idx on public.app_nc_programs (tenant_id, status);
alter table public.app_nc_programs enable row level security;

-- ---------- Расширить типы вложений ----------
create or replace function public.app_attachment_add(p_token uuid, p_entity_type text, p_entity_id uuid,
  p_name text, p_mime text, p_data text)
returns table (id uuid, name text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ulogin text; ten uuid; aid uuid; bytes bytea;
        allowed text[] := array['order','document','qc','passport','naryad','tender','nc','issue','service','tkp','deal','client'];
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.ulogin into ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if not (p_entity_type = any(allowed)) then raise exception 'Неизвестный тип сущности'; end if;
  if coalesce(trim(p_name),'') = '' then raise exception 'Укажите имя файла'; end if;
  begin bytes := decode(p_data, 'base64'); exception when others then raise exception 'Некорректные данные файла'; end;
  if octet_length(bytes) > 8388608 then raise exception 'Файл больше 8 МБ'; end if;
  insert into public.app_attachments (tenant_id, entity_type, entity_id, name, mime, size, data, uploaded_by)
  values (ten, p_entity_type, p_entity_id, trim(p_name), nullif(trim(p_mime),''), octet_length(bytes), bytes, ulogin)
  returning app_attachments.id into aid;
  return query select aid, trim(p_name);
end $$;

-- ---------- RPC ----------
create or replace function public.app_nc_list(p_token uuid, p_q text default null)
returns table (id uuid, order_id uuid, order_number text, equipment_id uuid, equipment text, detail text,
               program_no text, version integer, program_time_min numeric, status text, note text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select n.id, n.order_id, o.number, n.equipment_id, e.name, n.detail, n.program_no, n.version, n.program_time_min, n.status, n.note, n.created_at
    from public.app_nc_programs n
    left join public.app_orders o on o.id = n.order_id
    left join public.app_equipment e on e.id = n.equipment_id
    where (urole='admin' or n.tenant_id = ten)
      and (qq='' or lower(n.detail) like '%'||qq||'%' or lower(coalesce(n.program_no,'')) like '%'||qq||'%' or lower(coalesce(o.number,'')) like '%'||qq||'%')
    order by n.created_at desc;
end $$;

create or replace function public.app_nc_kpi(p_token uuid)
returns table (programs bigint, approved bigint, draft bigint, total_min numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select count(*),
    count(*) filter (where status='approved'),
    count(*) filter (where status='draft'),
    coalesce(sum(program_time_min),0)
    from public.app_nc_programs where (urole='admin' or tenant_id = ten);
end $$;

create or replace function public.app_nc_save(p_token uuid, p_id uuid, p_order_id uuid, p_equipment_id uuid, p_detail text,
  p_program_no text, p_time numeric, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','technologist','master') then return query select false,'Недостаточно прав'; return; end if;
  if coalesce(trim(p_detail),'') = '' then return query select false,'Укажите деталь'; return; end if;
  if p_id is null then
    insert into public.app_nc_programs (tenant_id, order_id, equipment_id, detail, program_no, program_time_min, note, created_login)
    values (ten, p_order_id, p_equipment_id, trim(p_detail), nullif(trim(p_program_no),''), p_time, nullif(trim(p_note),''), ulogin);
  else
    update public.app_nc_programs set order_id=p_order_id, equipment_id=p_equipment_id, detail=trim(p_detail),
      program_no=nullif(trim(p_program_no),''), program_time_min=p_time, note=nullif(trim(p_note),''), updated_at=now()
     where id=p_id and (urole='admin' or tenant_id=ten);
  end if;
  return query select true,'УП сохранена';
end $$;

create or replace function public.app_nc_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if p_status not in ('draft','approved','archive') then return query select false,'Неверный статус'; return; end if;
  update public.app_nc_programs set status=p_status, updated_at=now() where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Статус УП обновлён';
end $$;

grant execute on function public.app_nc_list(uuid,text) to anon, authenticated;
grant execute on function public.app_nc_kpi(uuid) to anon, authenticated;
grant execute on function public.app_nc_save(uuid,uuid,uuid,uuid,text,text,numeric,text) to anon, authenticated;
grant execute on function public.app_nc_set_status(uuid,uuid,text) to anon, authenticated;

-- ---------- Демо (тенант A) ----------
insert into public.app_nc_programs (tenant_id, order_id, equipment_id, detail, program_no, version, program_time_min, status, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001',
       (select id from public.app_orders where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' order by created_at limit 1),
       (select id from public.app_equipment where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and kind='frezerny' order by name limit 1),
       v.detail, v.pno, 1, v.tm, v.st, 'technologist'
from (values ('Пуансон, Ш-001.01.01','УП010135',480,'approved'), ('Матрица, Ш-001.02.01','УП010136',720,'draft')) as v(detail, pno, tm, st)
where not exists (select 1 from public.app_nc_programs where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('УП/NC','Как вести реестр управляющих программ?',
   'Модуль «УП/NC»: программа привязывается к заказу и станку, указывается деталь, номер программы (напр. УП010135), версия, время обработки и статус (черновик/апробирована/архив). Файлы программы прикрепляются к карточке. KPI: программ, апробировано, черновиков, суммарное время.',
   'УП NC управляющая программа реестр версия станок деталь G-код'),
  ('УП/NC','Связь УП с производством',
   'УП выбирается при наладке и выполнении операций (диспетчерская/производство). Время обработки из УП используется для нормирования и плана. Файлы УП хранятся в карточке (до 8 МБ).',
   'УП NC наладка операция нормирование производство файлы')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Как вести реестр управляющих программ?');
