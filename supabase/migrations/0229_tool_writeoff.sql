-- ============================================================
-- 3DMP Service · 0229_tool_writeoff.sql
-- X13 (остаток): авто-списание инструмента по операциям наряда.
-- При переводе операции наряда в «выполнено» инструмент из app_route_tools
-- списывается: наработка растёт на минуты операции × кол-во, статус → worn
-- при исчерпании ресурса. Журнал app_tool_usage (идемпотентно по операции).
-- Идемпотентно. Зависит от 0001..0228.
-- ============================================================

create table if not exists public.app_tool_usage (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid references public.tenants (id),
  tool_life_id uuid references public.app_tool_life (id) on delete cascade,
  naryad_id    uuid references public.app_naryads (id) on delete set null,
  naryad_op_id uuid references public.app_naryad_ops (id) on delete cascade,
  minutes      numeric not null default 0,
  note         text,
  by_login     text,
  created_at   timestamptz not null default now(),
  unique (tool_life_id, naryad_op_id)
);
create index if not exists app_tool_usage_tool_idx on public.app_tool_usage (tool_life_id);
alter table public.app_tool_usage enable row level security;

-- ---------- Отметка операции наряда: с авто-списанием инструмента ----------
create or replace function public.app_naryad_op_done(p_token uuid, p_op_id uuid, p_fact_hours numeric, p_done boolean)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare nid uuid; nnum text; left_c integer; ten uuid; ulog text;
        olddone boolean; rsid uuid; mins numeric; written integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.ulogin into ulog from public.app_session_user(p_token) s;
  select op.done, op.route_step_id, op.naryad_id into olddone, rsid, nid
    from public.app_naryad_ops op where op.id = p_op_id;
  if nid is null then return query select false,'Операция не найдена'; return; end if;

  update public.app_naryad_ops set done = coalesce(p_done, true), fact_hours = coalesce(p_fact_hours, fact_hours) where id = p_op_id;
  update public.app_naryads n set fact_hours = (select coalesce(sum(op.fact_hours),0) from public.app_naryad_ops op where op.naryad_id = n.id),
    updated_at = now() where n.id = nid;

  select n.number, n.tenant_id into nnum, ten from public.app_naryads n where n.id = nid;

  -- X13: авто-списание инструмента при переходе «не выполнено» → «выполнено»
  if coalesce(p_done, true) and not coalesce(olddone, false) and rsid is not null then
    mins := coalesce(nullif(p_fact_hours,0) * 60,
                     (select rs.plan_min from public.app_route_steps rs where rs.id = rsid), 0);
    if mins is null then mins := 0; end if;
    with ins as (
      insert into public.app_tool_usage (tenant_id, tool_life_id, naryad_id, naryad_op_id, minutes, note, by_login)
      select ten, rt.tool_life_id, nid, p_op_id, round(mins * coalesce(rt.qty,1), 1), 'Авто-списание по операции', ulog
        from public.app_route_tools rt
       where rt.route_step_id = rsid
         and not exists (select 1 from public.app_tool_usage u where u.tool_life_id = rt.tool_life_id and u.naryad_op_id = p_op_id)
      returning tool_life_id, minutes
    )
    update public.app_tool_life tl
       set used_min = coalesce(tl.used_min,0) + i.m,
           status = case when coalesce(tl.resource_min,0) > 0 and coalesce(tl.used_min,0) + i.m >= tl.resource_min then 'worn' else tl.status end
      from (select tool_life_id, sum(minutes) m from ins group by tool_life_id) i
     where tl.id = i.tool_life_id;
    get diagnostics written = row_count;
    if written > 0 then
      perform public.app_notif_roles_t(ten, array['admin','manager','master','supply'], 'Списание инструмента: наряд ' || nnum,
              'Списана наработка по операции (' || round(mins,1) || ' мин)', 'apps/tooling/index.html');
    end if;
  end if;

  select count(*) into left_c from public.app_naryad_ops op where op.naryad_id = nid and not op.done;
  if left_c = 0 then
    perform public.app_notif_roles_t(ten, array['admin','manager','owner','chief','master'], 'Наряд ' || nnum || ': все операции выполнены', 'Можно закрывать', 'apps/production/index.html');
  end if;
  return query select true,'Обновлено';
end $$;

grant execute on function public.app_naryad_op_done(uuid,uuid,numeric,boolean) to anon, authenticated;

-- ---------- История списаний инструмента ----------
create or replace function public.app_tool_usage_list(p_token uuid, p_tool_life_id uuid default null)
returns table (id uuid, tool text, tool_code text, naryad text, minutes numeric, note text, by_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select u.id, tl.name, tl.code, n.number, u.minutes, u.note, u.by_login, u.created_at
      from public.app_tool_usage u
      join public.app_tool_life tl on tl.id = u.tool_life_id
      left join public.app_naryads n on n.id = u.naryad_id
     where (adm or u.tenant_id = ten)
       and (p_tool_life_id is null or u.tool_life_id = p_tool_life_id)
     order by u.created_at desc
     limit 200;
end $$;

grant execute on function public.app_tool_usage_list(uuid,uuid) to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select null, v.category, v.question, v.answer, v.tags
from (values
  ('Инструмент','Авто-списание инструмента по операциям наряда (X13)',
   'При отметке операции наряда «выполнено» инструмент, привязанный к операции (app_route_tools ← шаг маршрута), списывается автоматически: наработка app_tool_life.used_min растёт на (минуты операции × количество инструмента), при исчерпании ресурса статус → «изношен» (worn); запись фиксируется в журнале app_tool_usage (идемпотентно по операции — повторная отметка не дублирует). История — RPC app_tool_usage_list; кнопка «Списания» в модуле «Инструмент».',
   'инструмент списание наработка стойкость операция наряд X13 app_tool_usage')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge k where k.question=v.question);
