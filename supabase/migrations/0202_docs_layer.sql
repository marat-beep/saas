-- ============================================================
-- 3DMP Service · 0202_docs_layer.sql  (X9 — общий слой документов/подписей/маршрутов)
-- Единый движок подписи и маршрутов поверх app_signatures (W17) и
-- app_approval_* (W10). Модули-потребители переключаются итеративно.
-- Идемпотентно. Зависит от 0001..0201.
-- ============================================================

create or replace function public.app_document_signatures(p_token uuid, p_entity_type text, p_entity_id uuid)
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
     where s.entity_type = p_entity_type and s.entity_id = p_entity_id and (adm or s.tenant_id = ten)
     order by s.signed_at desc;
end $$;

-- Единая подпись для любого типа сущности (docs/edo/kedo/service/…)
create or replace function public.app_document_sign(p_token uuid, p_entity_type text, p_entity_id uuid, p_method text, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; meth text; et text; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  et := lower(trim(coalesce(p_entity_type,'')));
  if et = '' or p_entity_id is null then return query select false,'Не указана сущность подписи'; return; end if;
  meth := coalesce(nullif(trim(p_method),''),'ПЭП');
  if meth not in ('ПЭП','УНЭП','УКЭП','Госключ') then return query select false,'Метод: ПЭП/УНЭП/УКЭП/Госключ'; return; end if;
  insert into public.app_signatures (tenant_id, entity_type, entity_id, signer_login, method, status, note)
  values (ten, et, p_entity_id, uname, meth, 'signed', nullif(trim(p_note),''));
  if et = 'hr_doc' then
    update public.app_hr_docs set status = 'signed', signed_at = now(), sign_method = meth, updated_at = now() where id = p_entity_id;
  elsif et = 'doc_flow' then
    update public.app_doc_flows set signature_method = meth, updated_at = now() where id = p_entity_id;
  end if;
  return query select true,'Подписано: ' || et || ' (' || meth || ')';
end $$;

-- Единый запуск маршрута для любой сущности (reuse W10)
create or replace function public.app_document_route_start(p_token uuid, p_entity_type text, p_entity_id uuid, p_route_id uuid, p_title text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare r record; et text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  et := lower(trim(coalesce(p_entity_type,'')));
  if et = '' or p_entity_id is null then return query select false,'Не указана сущность', null::uuid; return; end if;
  select * into r from public.app_approval_request_create(p_token, p_route_id, et, p_entity_id, coalesce(p_title,'Документ')) x;
  if not r.ok then return query select false, r.message, null::uuid; return; end if;
  return query select true, 'Маршрут запущен', r.id;
end $$;

-- Список доступных маршрутов по типу сущности (для UI общего слоя)
create or replace function public.app_document_routes(p_token uuid, p_entity_type text)
returns table (id uuid, name text, doc_type text, steps jsonb, active boolean)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; et text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  et := lower(trim(coalesce(p_entity_type,'')));
  return query
    select r.id, r.name, r.doc_type, r.steps, r.active
      from public.app_approval_routes r
     where (adm or r.tenant_id = ten) and coalesce(r.active,true)
       and (et = '' or r.doc_type = et or r.doc_type is null)
     order by r.name;
end $$;

-- ================= База знаний =================
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Единый слой документов/подписей/маршрутов (X9)',
   'Общий слой (X9): единая подпись app_document_sign (любой entity_type; пишет в app_signatures W17; для hr_doc/doc_flow обновляет статус/метод), список подписей app_document_signatures, запуск маршрута app_document_route_start (reuse app_approval_* W10), список маршрутов app_document_routes. JS-модуль assets/js/documents.js (window.AppDocuments.sign/signatures/startRoute/routes) — единый просмотр/подпись/маршрут для docs/edo/kedo/service. Модули переключаются на слой итеративно, без дублей RPC.',
   'документы подпись маршруты общий слой signatures approval единый движок')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001'
     and question = 'Единый слой документов/подписей/маршрутов (X9)'
);

-- ================= Права =================
grant execute on function public.app_document_signatures(uuid,text,uuid) to anon, authenticated;
grant execute on function public.app_document_sign(uuid,text,uuid,text,text) to anon, authenticated;
grant execute on function public.app_document_route_start(uuid,text,uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_document_routes(uuid,text) to anon, authenticated;
