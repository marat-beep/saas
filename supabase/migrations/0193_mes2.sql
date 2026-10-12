-- ============================================================
-- 3DMP Service · 0193_mes2.sql  (X11 — MES/терминал 2.0)
-- Срез очередей по РЦ (app_mes_board), переназначение РЦ/приоритета (app_op_reassign),
-- аварийный сигнал с рабочего места (app_alert_raise → app_issues), Realtime-публикация.
-- Идемпотентно. Зависит от 0001..0192.
-- ============================================================

-- Realtime: публикуем таблицы производства для живой доски MES
do $pub$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='app_naryad_ops') then
      execute 'alter publication supabase_realtime add table public.app_naryad_ops';
    end if;
    if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='app_naryads') then
      execute 'alter publication supabase_realtime add table public.app_naryads';
    end if;
  end if;
end $pub$;

-- ================= RPC: срез очередей по РЦ =================
drop function if exists public.app_mes_board(uuid);
create or replace function public.app_mes_board(p_token uuid, p_wc_id uuid default null)
returns table (wc_id uuid, wc_name text, queue bigint, work bigint, paused bigint, done bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select n.wc_id, coalesce(w.name, '— без центра —'),
           count(*) filter (where op.mes_status = 'queue'),
           count(*) filter (where op.mes_status = 'work'),
           count(*) filter (where op.mes_status = 'paused'),
           count(*) filter (where op.mes_status = 'done')
      from public.app_naryad_ops op join public.app_naryads n on n.id = op.naryad_id
      left join public.app_work_centers w on w.id = n.wc_id
     where (urole = 'admin' or n.tenant_id = ten) and (p_wc_id is null or n.wc_id = p_wc_id)
     group by n.wc_id, w.name
     order by w.name nulls last;
end $$;

-- ================= RPC: переназначение РЦ/приоритета =================
create or replace function public.app_op_reassign(p_token uuid, p_op_id uuid, p_wc_id uuid, p_priority text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; nid uuid; pr text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select op.naryad_id into nid from public.app_naryad_ops op join public.app_naryads n on n.id = op.naryad_id
   where op.id = p_op_id and (urole = 'admin' or n.tenant_id = ten);
  if nid is null then return query select false,'Операция не найдена'; return; end if;
  pr := nullif(trim(coalesce(p_priority,'')),'');
  if pr is not null and pr not in ('high','normal','low') then return query select false,'Недопустимый приоритет'; return; end if;
  update public.app_naryads n set wc_id = coalesce(p_wc_id, n.wc_id), priority = coalesce(pr, n.priority), updated_at = now()
   where n.id = nid;
  return query select true,'Задание переназначено';
end $$;

-- ================= RPC: аварийный сигнал =================
create or replace function public.app_alert_raise(p_token uuid, p_op_id uuid, p_kind text, p_text text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; nid uuid; oid uuid; nnum text; newid uuid; kd text; ttl text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if p_op_id is not null then
    select n.id, n.order_id, n.number into nid, oid, nnum
      from public.app_naryad_ops op join public.app_naryads n on n.id = op.naryad_id
     where op.id = p_op_id and (public.app_is_platform_admin(p_token) or n.tenant_id = ten);
  end if;
  kd := coalesce(nullif(trim(p_kind),''),'сбой');
  ttl := 'MES/сигнал: ' || kd || coalesce(' · ' || nnum, '');
  insert into public.app_issues (tenant_id, title, description, priority, source, status, assignee, order_id, escalated, escalated_at, created_login)
  values (ten, left(ttl,200), nullif(trim(p_text),''), 'critical', 'mes', 'open', null, oid, true, now(), uname)
  returning app_issues.id into newid;
  perform public.app_notif_roles_t(ten, array['admin','owner','manager','chief','master'], ttl, coalesce(left(p_text,180),''), 'apps/issues/index.html');
  return query select true,'Сигнал принят: создана проблема', newid;
end $$;

create or replace function public.app_mes_alerts(p_token uuid)
returns table (id uuid, title text, status text, priority text, created_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select i.id, i.title, i.status, i.priority, i.created_login, i.created_at
      from public.app_issues i where (adm or i.tenant_id = ten) and i.source = 'mes'
     order by i.created_at desc limit 50;
end $$;

-- ================= База знаний =================
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Производство','MES/терминал 2.0: живая доска, переназначение, аварийный сигнал (X11)',
   'MES 2.0: срез очередей по рабочим центрам (app_mes_board: queue/work/paused/done), переназначение РЦ и приоритета задания перетаскиванием/диалогом (app_op_reassign), аварийный сигнал с рабочего места (app_alert_raise — создаёт критическую проблему в app_issues и уведомляет; список app_mes_alerts). Доска обновляется в реальном времени (Realtime-публикация app_naryad_ops/app_naryads). Терминал: офлайн-очередь, скан, сигнал.',
   'MES доска очередь рабочий центр переназначение приоритет аварийный сигнал проблема realtime терминал')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001'
     and question = 'MES/терминал 2.0: живая доска, переназначение, аварийный сигнал (X11)'
);

-- ================= Права =================
grant execute on function public.app_mes_board(uuid,uuid) to anon, authenticated;
grant execute on function public.app_op_reassign(uuid,uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_alert_raise(uuid,uuid,text,text) to anon, authenticated;
grant execute on function public.app_mes_alerts(uuid) to anon, authenticated;
