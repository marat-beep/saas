-- ============================================================
-- 3DMP Service · 0045_links.sql  (v27.0 — связки данных)
-- Авто-КП и авто-счёт из заявки, наряд из спецификации (BOM), списание материалов.
-- База знаний. Tenant-изоляция. Зависит от 0001..0044.
-- ============================================================

-- ---------- Авто-КП из заявки ----------
create or replace function public.app_order_create_quote(p_token uuid, p_order_id uuid, p_valid_days integer default 30)
returns table (id uuid, number text, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; ten uuid; o record; amt numeric; did uuid; dnum text; vd date;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select o0.* into o from public.app_orders o0 where o0.id = p_order_id;
  if o.id is null then raise exception 'Заявка не найдена'; end if;

  amt := o.amount;
  if amt is null then
    select c.total into amt from public.app_bom b, lateral public.app_bom_cost(p_token, b.id, coalesce(b.qty,1)) c
      where b.order_id = p_order_id limit 1;
  end if;
  vd := current_date + greatest(coalesce(p_valid_days,30),1);
  dnum := 'KP-' || lpad(nextval('public.app_doc_seq')::text, 5, '0');
  insert into public.app_documents (tenant_id, doc_type, number, title, order_id, customer_id, amount, valid_until, status, content, created_by, created_login)
  values (ten, 'kp', dnum, 'КП по заявке ' || o.number, p_order_id, o.customer_id, amt, vd, 'draft',
          'Коммерческое предложение по заявке ' || o.number || '.', uid, ulogin)
  returning app_documents.id into did;
  insert into public.app_document_versions (document_id, version, title, content, by_login)
  values (did, 1, 'КП по заявке ' || o.number, 'Коммерческое предложение.', ulogin);
  return query select did, dnum, 'КП создано';
end $$;

-- ---------- Авто-счёт из заявки/договора ----------
create or replace function public.app_order_create_invoice(p_token uuid, p_order_id uuid, p_due_days integer default 14)
returns table (id uuid, number text, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; ten uuid; o record; amt numeric; inum text; iid uuid; did_link uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select o0.* into o from public.app_orders o0 where o0.id = p_order_id;
  if o.id is null then raise exception 'Заявка не найдена'; end if;

  amt := o.amount;
  if amt is null or amt = 0 then
    select c.total into amt from public.app_bom b, lateral public.app_bom_cost(p_token, b.id, coalesce(b.qty,1)) c
      where b.order_id = p_order_id limit 1;
  end if;
  if amt is null or amt = 0 then raise exception 'Не удалось определить сумму — укажите сумму заявки или спецификацию'; end if;

  select d.id into did_link from public.app_documents d
    where d.order_id = p_order_id and d.doc_type = 'contract' order by d.created_at desc limit 1;

  inum := 'INV-' || lpad(nextval('public.app_invoice_seq')::text, 5, '0');
  insert into public.app_invoices (tenant_id, number, order_id, customer, customer_id, document_id, amount, status, due_date, created_by, created_login)
  values (ten, inum, p_order_id, o.customer, o.customer_id, did_link, amt, 'draft', current_date + greatest(coalesce(p_due_days,14),1), uid, ulogin)
  returning app_invoices.id into iid;
  return query select iid, inum, 'Счёт создан по заявке';
end $$;

-- ---------- Наряд из спецификации (BOM) ----------
create or replace function public.app_naryad_from_bom(p_token uuid, p_bom_id uuid, p_wc_id uuid, p_assignee text, p_due_date date)
returns table (id uuid, number text, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; ten uuid; b record; nid uuid; nnum text; i integer := 0; ln record;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select b0.* into b from public.app_bom b0 where b0.id = p_bom_id;
  if b.id is null then raise exception 'Спецификация не найдена'; end if;

  nnum := 'NAR-' || lpad(nextval('public.app_naryad_seq')::text, 5, '0');
  insert into public.app_naryads (number, order_id, title, wc_id, assignee, status, priority, start_date, due_date, tenant_id, created_by, created_login)
  values (nnum, b.order_id, coalesce(b.product,'Наряд по спецификации'), p_wc_id, nullif(trim(p_assignee),''), 'open', 'normal', current_date, p_due_date, ten, uid, ulogin)
  returning app_naryads.id into nid;

  for ln in select * from public.app_bom_lines where bom_id = p_bom_id and item_type = 'operation' order by seq loop
    i := i + 1;
    insert into public.app_naryad_ops (naryad_id, seq, operation, operation_id, worker, plan_hours)
    values (nid, i, coalesce(ln.name,'Операция'), ln.operation_id, nullif(trim(p_assignee),''), coalesce(ln.norm_hours,0));
  end loop;

  update public.app_naryads n set plan_hours = (select coalesce(sum(op.plan_hours),0) from public.app_naryad_ops op where op.naryad_id = n.id),
    status = 'in_progress' where n.id = nid;
  return query select nid, nnum, 'Наряд создан по спецификации';
end $$;

-- ---------- Списание материалов по спецификации ----------
create or replace function public.app_bom_writeoff(p_token uuid, p_bom_id uuid, p_order_id uuid, p_qty numeric default 1)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare b record; ln record; rec record; cnt integer := 0; k numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select b0.* into b from public.app_bom b0 where b0.id = p_bom_id;
  if b.id is null then return query select false,'Спецификация не найдена'; return; end if;
  k := greatest(coalesce(p_qty,1),1);

  for ln in select * from public.app_bom_lines where bom_id = p_bom_id and item_type='material' and material_id is not null order by seq loop
    for rec in select * from public.app_stock_move(p_token, ln.material_id, 'out', coalesce(ln.qty,0)*k, 0, 'Списание по спецификации', 'bom', p_order_id, null) loop
      if rec.ok then cnt := cnt + 1; end if;
    end loop;
  end loop;
  return query select true, 'Списано позиций: ' || cnt;
end $$;

grant execute on function public.app_order_create_quote(uuid,uuid,integer) to anon, authenticated;
grant execute on function public.app_order_create_invoice(uuid,uuid,integer) to anon, authenticated;
grant execute on function public.app_naryad_from_bom(uuid,uuid,uuid,text,date) to anon, authenticated;
grant execute on function public.app_bom_writeoff(uuid,uuid,uuid,numeric) to anon, authenticated;

-- ---------- База знаний: связки ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Связки','Как быстро создать КП и счёт из заявки?',
   'В карточке заявки есть кнопки «Создать КП» и «Создать счёт»: КП создаётся на сумму заявки (или из спецификации), с сроком действия; счёт — со сроком оплаты и привязкой к договору, если он есть. Так замыкается цепочка: заявка → КП → договор → счёт → оплата без ручного переноса.',
   'связки КП счёт заявка авто договор оплата'),
  ('Связки','Как перейти от спецификации к производству и складу?',
   'В карточке спецификации (BOM) есть кнопки «Создать наряд» (операции и нормо-часы переносятся в наряд) и «Списать материалы» (расход материалов по спецификации со склада, с проверкой остатков). Это единый поток: BOM → наряд → склад → себестоимость.',
   'связки BOM наряд склад списание материалы производство')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and category='Связки');
