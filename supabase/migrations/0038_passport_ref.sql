-- ============================================================
-- 3DMP Service · 0038_passport_ref.sql  (v20.0 — переработка «Паспорт изделия»)
-- Серийный номер, количество, связи наряд/ОТК/заявка, статус. QR-метка (UI).
-- База знаний. Tenant-изоляция. Зависит от 0001..0037.
-- ============================================================

alter table public.app_passports add column if not exists naryad_id uuid references public.app_naryads (id) on delete set null;
alter table public.app_passports add column if not exists serial    text;
alter table public.app_passports add column if not exists qty       numeric;
alter table public.app_passports add column if not exists status    text not null default 'active'; -- active | archived
create index if not exists app_passports_naryad_idx on public.app_passports (naryad_id);

-- ---------- Список паспортов (расширенный) ----------
drop function if exists public.app_passport_list(uuid);
create or replace function public.app_passport_list(p_token uuid)
returns table (id uuid, number text, product text, serial text, qty numeric, status text,
               order_id uuid, order_number text, qc_check_id uuid, qc_number text, naryad_number text,
               created_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select p.id, p.number, p.product, p.serial, p.qty, p.status, p.order_id, o.number, p.qc_check_id, c.number, n.number,
           p.created_login, p.created_at
    from public.app_passports p
    left join public.app_orders o on o.id = p.order_id
    left join public.app_qc_checks c on c.id = p.qc_check_id
    left join public.app_naryads n on n.id = p.naryad_id
    where (urole='admin' or p.tenant_id = ten)
    order by p.created_at desc;
end $$;

-- ---------- Карточка паспорта (расширенная) ----------
drop function if exists public.app_passport_get(uuid,uuid);
create or replace function public.app_passport_get(p_token uuid, p_id uuid)
returns table (id uuid, number text, product text, serial text, qty numeric, status text,
               order_id uuid, order_number text, naryad_id uuid, naryad_number text,
               qc_check_id uuid, qc_number text, data jsonb, created_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select p.id, p.number, p.product, p.serial, p.qty, p.status, p.order_id, o.number, p.naryad_id, n.number,
           p.qc_check_id, c.number, p.data, p.created_login, p.created_at
    from public.app_passports p
    left join public.app_orders o on o.id = p.order_id
    left join public.app_naryads n on n.id = p.naryad_id
    left join public.app_qc_checks c on c.id = p.qc_check_id
    where p.id = p_id and (urole='admin' or p.tenant_id = ten);
end $$;

-- ---------- Создать паспорт ----------
drop function if exists public.app_passport_create(uuid,uuid,text,uuid,jsonb);
create or replace function public.app_passport_create(p_token uuid, p_order_id uuid, p_product text, p_qc_check_id uuid, p_data jsonb,
  p_naryad_id uuid default null, p_serial text default null, p_qty numeric default null)
returns table (id uuid, number text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ulogin text; ten uuid; pid uuid; pnum text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_product),'') = '' then raise exception 'Укажите изделие'; end if;
  pnum := 'PAS-' || lpad(nextval('public.app_passport_seq')::text, 5, '0');
  insert into public.app_passports (tenant_id, number, order_id, product, qc_check_id, data, naryad_id, serial, qty, created_by, created_login)
  values (ten, pnum, p_order_id, trim(p_product), p_qc_check_id, coalesce(p_data,'{}'::jsonb), p_naryad_id, nullif(trim(p_serial),''), p_qty, uid, ulogin)
  returning app_passports.id into pid;
  perform public.app_notif_roles_t(ten, array['admin','manager','owner','qc','master'], 'Паспорт ' || pnum, trim(p_product), 'apps/passport/index.html');
  return query select pid, pnum;
end $$;

grant execute on function public.app_passport_list(uuid) to anon, authenticated;
grant execute on function public.app_passport_get(uuid,uuid) to anon, authenticated;
grant execute on function public.app_passport_create(uuid,uuid,text,uuid,jsonb,uuid,text,numeric) to anon, authenticated;

-- ---------- База знаний: паспорт ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Паспорт','Что такое паспорт изделия и зачем QR?',
   'Паспорт — цифровой документ изделия: номер, изделие, серийный номер, количество, связи с заявкой, нарядом и чек-листом ОТК, а также данные (материал, примечания). QR-метка на карточке ведёт на страницу паспорта — при сканировании открывается вся история изделия.',
   'паспорт изделие QR серийный номер история'),
  ('Паспорт','Как связаны паспорт, ОТК и трассируемость?',
   'Если у паспорта указан чек-лист ОТК, в карточке доступна трассируемость: заявка → наряд → операции → материалы → дефекты. Так паспорт опирается на реальные данные, а не на ручной ввод, и подтверждает качество изделия.',
   'паспорт ОТК трассируемость качество связь')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and category='Паспорт');
