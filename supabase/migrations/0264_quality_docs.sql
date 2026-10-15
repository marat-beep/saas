-- ============================================================
-- 3DMP Service · 0264_quality_docs.sql  (R4 · PROP-26 — сертификаты/декларации и LIMS)
-- Реестр сертификатов/деклараций/протоколов испытаний со сроком действия.
-- ВНИМАНИЕ: имя таблицы отличать от существующей app_certificates (кадровые удостоверения, 0199).
-- Идемпотентно.
-- ============================================================

create table if not exists public.app_quality_certificates (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  kind text not null default 'certificate',  -- certificate|declaration|protocol
  number text,
  issued_by text,
  product text,
  valid_from date,
  valid_to date,
  note text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists app_quality_certificates_idx on public.app_quality_certificates (tenant_id, valid_to);

create or replace function public.app_certificate_list(p_token uuid)
returns table (id uuid, kind text, number text, issued_by text, product text, valid_from date, valid_to date, note text, expired boolean, expiring boolean)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select c.id, c.kind, c.number, c.issued_by, c.product, c.valid_from, c.valid_to, c.note,
      (c.valid_to is not null and c.valid_to < current_date),
      (c.valid_to is not null and c.valid_to >= current_date and c.valid_to <= current_date + 30)
    from public.app_quality_certificates c where (urole = 'admin' or c.tenant_id = ten) order by c.valid_to nulls last;
end $$;
grant execute on function public.app_certificate_list(uuid) to anon, authenticated;

create or replace function public.app_certificate_save(p_token uuid, p_id uuid, p_kind text, p_number text, p_issued_by text, p_product text, p_valid_from date, p_valid_to date, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid; rid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_number), '') = '' then return query select false, 'Укажите номер'; return; end if;
  if p_id is null then
    insert into public.app_quality_certificates (tenant_id, kind, number, issued_by, product, valid_from, valid_to, note, active)
    values (ten, coalesce(p_kind, 'certificate'), p_number, p_issued_by, p_product, p_valid_from, p_valid_to, p_note, true) returning id into rid;
  else
    update public.app_quality_certificates set kind = coalesce(p_kind, kind), number = p_number, issued_by = p_issued_by,
      product = p_product, valid_from = p_valid_from, valid_to = p_valid_to, note = p_note
      where id = p_id and (urole = 'admin' or tenant_id = ten) returning id into rid;
  end if;
  if rid is null then return query select false, 'Не найдено'; return; end if;
  return query select true, 'Сохранено';
end $$;
grant execute on function public.app_certificate_save(uuid,uuid,text,text,text,text,date,date,text) to anon, authenticated;

create or replace function public.app_certificate_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_quality_certificates where id = p_id and (urole = 'admin' or tenant_id = ten);
  return query select true, 'Удалено';
end $$;
grant execute on function public.app_certificate_delete(uuid,uuid) to anon, authenticated;
