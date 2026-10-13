-- ============================================================
-- 3DMP Service · 0228_settings_apply3.sql
-- U7: применение настроек мастера без регрессий.
--  • docs.number_prefix — префикс номера документов БЕЗ явного типа
--    (kp/contract/techcard/act сохраняют свои префиксы; по умолчанию 'DOC-').
--  • service.sla_response_hours — базовый норматив реакции для приоритета
--    'normal' (только если настройка задана; SLA из контракта имеет приоритет;
--    если настройки нет — прежнее поведение по приоритету).
-- Идемпотентно. Зависит от 0001..0227.
-- ============================================================

-- ---------- Документы: префикс из настроек для документов без типа ----------
drop function if exists public.app_doc_create(uuid,text,text,uuid,text,numeric,text);
create or replace function public.app_doc_create(p_token uuid, p_doc_type text, p_title text, p_order_id uuid,
  p_counterparty text, p_amount numeric, p_content text,
  p_customer_id uuid default null, p_valid_until date default null, p_assignee text default null)
returns table (id uuid, number text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; ten uuid; did uuid; dnum text; prefix text; dtype text; cname text; setpref text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_title),'') = '' then raise exception 'Укажите название документа'; end if;
  dtype := coalesce(nullif(trim(p_doc_type),''),'kp');
  if dtype in ('kp','contract','techcard','act') then
    prefix := case dtype when 'kp' then 'KP' when 'contract' then 'DOG' when 'techcard' then 'TC' else 'ACT' end;
  else
    -- U7: префикс из настроек docs.number_prefix (убираем хвостовые '-'); по умолчанию DOC
    setpref := nullif(regexp_replace(coalesce(public.app_setting_get(p_token,'docs','number_prefix','DOC'),'DOC'), '[\s-]+$', '', 'g'), '');
    prefix := coalesce(setpref, 'DOC');
  end if;
  if p_customer_id is not null then
    select c.name into cname from public.app_customers c where c.id = p_customer_id and (ten is null or c.tenant_id = ten);
  end if;
  dnum := prefix || '-' || lpad(nextval('public.app_doc_seq')::text, 5, '0');
  insert into public.app_documents (tenant_id, doc_type, number, title, order_id, counterparty, customer_id, amount,
                                    valid_until, assignee, content, created_by, created_login)
  values (ten, dtype, dnum, trim(p_title), p_order_id, coalesce(cname, nullif(trim(p_counterparty),'')),
          p_customer_id, p_amount, p_valid_until, nullif(trim(p_assignee),''), p_content, uid, ulogin)
  returning app_documents.id into did;
  insert into public.app_document_versions (document_id, version, title, content, by_login)
  values (did, 1, trim(p_title), p_content, ulogin);
  return query select did, dnum;
end $$;

grant execute on function public.app_doc_create(uuid,text,text,uuid,text,numeric,text,uuid,date,text) to anon, authenticated;

-- ---------- Сервис: базовый норматив реакции из настроек ----------
create or replace function public.app_service_save(
  p_token uuid, p_id uuid, p_customer_id uuid, p_equipment_id uuid, p_title text, p_kind text,
  p_scheduled_date date, p_engineer text, p_works text, p_cost numeric, p_note text,
  p_priority text default null, p_channel text default null, p_is_warranty boolean default null,
  p_contact text default null, p_location text default null, p_assigned_login text default null
) returns table (id uuid, number text, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; sid uuid; snum text; pr text; sh text;
        respmin integer; resmin integer; wid uuid; kid uuid; cresp integer; cres integer; iswar boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; return; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','chief','master','support') then raise exception 'Недостаточно прав'; return; end if;
  if coalesce(trim(p_title),'') = '' then raise exception 'Укажите тему'; return; end if;
  pr := coalesce(nullif(trim(p_priority),''),'normal');
  if pr not in ('low','normal','high','critical') then raise exception 'Неверный приоритет'; return; end if;
  select resp_min, res_min into respmin, resmin from public.app_service_sla_minutes(pr);

  -- U7: базовый норматив реакции (часы) из настроек — только для 'normal' и только если задан
  if pr = 'normal' then
    sh := public.app_setting_get(p_token, 'service', 'sla_response_hours', '');
    if coalesce(trim(sh),'') ~ '^[0-9]+(\.[0-9]+)?$' then
      respmin := ceil(sh::numeric * 60)::int;
    end if;
  end if;

  -- авто-гарантия по оборудованию
  if p_equipment_id is not null then
    select w.id into wid from public.app_warranties w
     where w.equipment_id = p_equipment_id and w.active and w.start_date <= current_date
       and (w.end_date is null or w.end_date >= current_date)
     order by w.end_date desc nulls last limit 1;
  end if;
  iswar := (wid is not null) or coalesce(p_is_warranty, false);

  -- SLA из активного контракта заказчика (имеет приоритет над настройками)
  if p_customer_id is not null then
    select k.id, k.response_sla_min, k.resolve_sla_min into kid, cresp, cres
      from public.app_service_contracts k
     where k.customer_id = p_customer_id and k.active and k.start_date <= current_date
       and (k.end_date is null or k.end_date >= current_date)
     order by k.end_date desc nulls last limit 1;
    if cresp is not null then respmin := cresp; end if;
    if cres is not null then resmin := cres; end if;
  end if;

  if p_id is null then
    snum := 'SRV-' || lpad(nextval('public.app_service_seq')::text, 5, '0');
    insert into public.app_service_requests
      (tenant_id, number, customer_id, equipment_id, title, kind, priority, channel, is_warranty, warranty_id, contract_id,
       contact, location, scheduled_date, engineer, assigned_login, works, cost, note, reported_at, response_due, resolve_due, created_login)
    values (ten, snum, p_customer_id, p_equipment_id, trim(p_title), coalesce(nullif(trim(p_kind),''),'service'), pr,
            coalesce(nullif(trim(p_channel),''),'manual'), iswar, wid, kid,
            nullif(trim(p_contact),''), nullif(trim(p_location),''), p_scheduled_date, nullif(trim(p_engineer),''), nullif(trim(p_assigned_login),''),
            nullif(trim(p_works),''), p_cost, nullif(trim(p_note),''), now(),
            now() + make_interval(mins => respmin), now() + make_interval(mins => resmin), ulogin)
    returning id into sid;
    insert into public.app_service_history (tenant_id, request_id, kind, text, by_login)
    values (ten, sid, 'event', 'Заявка создана (' || pr || (case when iswar then ', гарантия' else '' end) || ')', ulogin);
    perform public.app_notif_roles_t(ten, array['admin','owner','manager','director','chief','master','support'],
            'Сервис: новая заявка ' || snum, trim(p_title), 'apps/service/index.html');
    return query select sid, snum, 'Заявка создана';
  else
    update public.app_service_requests set customer_id=p_customer_id, equipment_id=p_equipment_id, title=trim(p_title),
      kind=coalesce(nullif(trim(p_kind),''),kind), priority=pr, channel=coalesce(nullif(trim(p_channel),''),channel),
      is_warranty=iswar, warranty_id=coalesce(wid, warranty_id), contact=nullif(trim(p_contact),''), location=nullif(trim(p_location),''),
      scheduled_date=p_scheduled_date, engineer=nullif(trim(p_engineer),''), assigned_login=nullif(trim(p_assigned_login),''),
      works=nullif(trim(p_works),''), cost=p_cost, note=nullif(trim(p_note),''), updated_at=now()
     where id=p_id and (urole='admin' or tenant_id=ten) returning id, number into sid, snum;
    insert into public.app_service_history (tenant_id, request_id, kind, text, by_login)
    values (ten, sid, 'event', 'Заявка изменена', ulogin);
    return query select sid, snum, 'Заявка обновлена';
  end if;
end $$;

grant execute on function public.app_service_save(uuid,uuid,uuid,uuid,text,text,date,text,text,numeric,text,text,text,boolean,text,text,text) to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select null, v.category, v.question, v.answer, v.tags
from (values
  ('Настройки','Применение настроек docs.number_prefix и service.sla_response_hours',
   'Мастер настройки сохраняет параметры в app_tenant_settings. docs.number_prefix влияет на номер документов без явного типа (общие DOC): задайте напр. «3DMP-» — общие документы получат номер 3DMP-00001; типовые (КП/договор/техкарта/акт) сохраняют префиксы KP/DOG/TC/ACT. service.sla_response_hours задаёт базовый норматив реакции (часы) для заявок с приоритетом «обычный»: если настройка задана — применяется; SLA из активного контракта заказчика имеет приоритет; для критичных/высоких используется SLA по приоритету.',
   'настройки мастер number_prefix sla_response_hours документы нумерация сервис норматив реакции применение')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge k where k.question=v.question);
