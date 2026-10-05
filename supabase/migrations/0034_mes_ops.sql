-- ============================================================
-- 3DMP Service · 0034_mes_ops.sql  (v16.1 — MES на операциях нарядов)
-- Диспетчерская работаем поверх операций нарядов (единый источник):
-- статус операции (очередь/работа/пауза/готово), факт, привязка к РЦ.
-- Tenant-изоляция. Зависит от 0001..0033.
-- ============================================================

alter table public.app_naryad_ops add column if not exists mes_status  text not null default 'queue'; -- queue|work|paused|done
alter table public.app_naryad_ops add column if not exists started_at  timestamptz;
alter table public.app_naryad_ops add column if not exists finished_at timestamptz;
create index if not exists app_naryad_ops_mes_idx on public.app_naryad_ops (mes_status);

update public.app_naryad_ops set mes_status = 'done' where done and mes_status <> 'done';

-- ---------- Доска диспетчера ----------
create or replace function public.app_mes_ops_board(p_token uuid, p_wc_id uuid default null)
returns table (op_id uuid, naryad_id uuid, naryad_number text, naryad_title text, wc_id uuid, wc_name text,
               seq integer, operation text, worker text, plan_hours numeric, fact_hours numeric,
               mes_status text, priority text, due_date date, assignee text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select op.id, n.id, n.number, n.title, n.wc_id, w.name, op.seq, op.operation, coalesce(op.worker, n.assignee),
           op.plan_hours, op.fact_hours, op.mes_status, n.priority, n.due_date, n.assignee
    from public.app_naryad_ops op
    join public.app_naryads n on n.id = op.naryad_id
    left join public.app_work_centers w on w.id = n.wc_id
    where (urole = 'admin' or n.tenant_id = ten)
      and (p_wc_id is null or n.wc_id = p_wc_id)
    order by case op.mes_status when 'work' then 0 when 'paused' then 1 when 'queue' then 2 else 3 end,
             case n.priority when 'high' then 0 when 'normal' then 1 else 2 end, n.due_date nulls last, op.seq;
end $$;

-- ---------- Сменить статус операции ----------
create or replace function public.app_mes_ops_set_status(p_token uuid, p_op_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ulogin text; ten uuid; nid uuid; nnum text; st text; left_c integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  st := case when p_status in ('queue','work','paused','done') then p_status else null end;
  if st is null then return query select false,'Недопустимый статус'; return; end if;
  select op.naryad_id, n.number into nid, nnum
    from public.app_naryad_ops op join public.app_naryads n on n.id = op.naryad_id
    where op.id = p_op_id and (urole = 'admin' or n.tenant_id = ten);
  if nid is null then return query select false,'Операция не найдена'; return; end if;

  update public.app_naryad_ops set mes_status = st,
    done = (st = 'done'),
    started_at = case when st = 'work' and started_at is null then now() else started_at end,
    finished_at = case when st = 'done' then coalesce(finished_at, now()) else null end
   where id = p_op_id;

  update public.app_naryads n set fact_hours = (select coalesce(sum(op.fact_hours),0) from public.app_naryad_ops op where op.naryad_id = n.id),
    status = case when n.status = 'open' and st = 'work' then 'in_progress' else n.status end,
    updated_at = now()
   where n.id = nid;

  if st = 'done' then
    select count(*) into left_c from public.app_naryad_ops op where op.naryad_id = nid and not op.done;
    perform public.app_notif_roles_t(ten, array['admin','manager','owner','chief','master'],
      case when left_c = 0 then 'Наряд ' || nnum || ': все операции выполнены' else 'Операция выполнена (' || nnum || ')' end,
      'Изменил: ' || coalesce(ulogin,''), 'apps/production/index.html');
  end if;
  return query select true,'Статус операции обновлён';
end $$;

grant execute on function public.app_mes_ops_board(uuid,uuid) to anon, authenticated;
grant execute on function public.app_mes_ops_set_status(uuid,uuid,text) to anon, authenticated;

-- ---------- База знаний: MES ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Диспетчерская','Что показывает MES-доска и как ей пользоваться?',
   'Диспетчерская показывает операции нарядов по рабочим центрам в четырёх колонках: «В очереди», «В работе», «Пауза», «Выполнено». Переталкивайте операции кнопками: Запустить → Пауза/Продолжить → Готово. Готово автоматически ставит факт и, когда все операции наряда выполнены, уведомляет о готовности к закрытию. Источник данных — операции нарядов (модуль «Производство»).',
   'MES диспетчерская канбан операция очередь работа пауза готово'),
  ('Диспетчерская','Связь MES с нарядами и рабочими центрами',
   'Каждая карточка — операция конкретного наряда: номер наряда, операция, рабочий центр, исполнитель, план/факт часов, приоритет и срок. Фильтр по рабочему центру показывает только его загрузку. Итог прозрачен: MES и «Производство» — один источник (операции наряда).',
   'MES наряд операция рабочий центр фильтр загрузка')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and category='Диспетчерская');
