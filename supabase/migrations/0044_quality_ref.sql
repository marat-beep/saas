-- ============================================================
-- 3DMP Service · 0044_quality_ref.sql  (v26.0 — переработка «СМК/метрология»)
-- Поверка СИ как действие (+уведомления), срок до поверки, трассируемость с паспортом.
-- База знаний. Зависит от 0001..0043.
-- ============================================================

alter table public.app_measuring_tools add column if not exists note text;

-- ---------- СИ: список (расширенный) ----------
drop function if exists public.app_tools_list(uuid);
create or replace function public.app_tools_list(p_token uuid)
returns table (id uuid, name text, serial text, tool_type text, location text,
               last_verified date, next_verified date, days_left integer, status text, note text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select t.id, t.name, t.serial, t.tool_type, t.location, t.last_verified, t.next_verified,
      case when t.next_verified is null then null else (t.next_verified - current_date) end,
      case when t.next_verified is null then 'none'
           when t.next_verified < current_date then 'expired'
           when t.next_verified < current_date + 30 then 'due'
           else 'ok' end,
      t.note
    from public.app_measuring_tools t
    where (urole='admin' or t.tenant_id = ten)
    order by case when t.next_verified is null then 1 else 0 end, t.next_verified;
end $$;

-- ---------- Поверка СИ (действие) ----------
create or replace function public.app_tool_verify(p_token uuid, p_id uuid, p_date date, p_next date)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; tname text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select t.name into tname from public.app_measuring_tools t where t.id = p_id and (urole='admin' or t.tenant_id = ten);
  if tname is null then return query select false,'СИ не найдено'; return; end if;
  if coalesce(p_date, current_date) is null then return query select false,'Укажите дату поверки'; return; end if;
  update public.app_measuring_tools set last_verified = coalesce(p_date, current_date), next_verified = p_next where id = p_id;
  perform public.app_notif_roles_t(ten, array['admin','owner','manager','qc','chief'], 'Поверка СИ: ' || tname,
    'Поверено ' || coalesce(p_date, current_date)::text || case when p_next is not null then ', следующая ' || p_next::text else '' end,
    'apps/quality/index.html');
  return query select true,'Поверка зарегистрирована';
end $$;

-- ---------- Трассируемость (с паспортом/примечанием) ----------
drop function if exists public.app_trace_list(uuid);
create or replace function public.app_trace_list(p_token uuid)
returns table (id uuid, item text, serial text, order_id uuid, order_number text, passport_id uuid, passport_number text,
               material text, operator text, note text, by_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select tr.id, tr.item, tr.serial, tr.order_id, o.number, tr.passport_id, p.number,
    tr.material, tr.operator, tr.note, tr.by_login, tr.created_at
    from public.app_traceability tr
    left join public.app_orders o on o.id = tr.order_id
    left join public.app_passports p on p.id = tr.passport_id
    where (urole='admin' or tr.tenant_id = ten) order by tr.created_at desc;
end $$;

-- app_trace_add: привязка паспорта уже есть в подписи (0022), оставляем.

grant execute on function public.app_tools_list(uuid) to anon, authenticated;
grant execute on function public.app_tool_verify(uuid,uuid,date,date) to anon, authenticated;
grant execute on function public.app_trace_list(uuid) to anon, authenticated;

-- ---------- База знаний: СМК ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('СМК','Как вести средства измерений и поверку?',
   'В «Качестве» (СМК) вкладка «Средства измерений»: карточки СИ со статусом — «в норме», «истекает» (≤30 дней), «просрочено». При проведении поверки укажите дату и следующую дату — запись обновится, а ответственным уйдёт уведомление. Просроченные СИ нельзя использовать по СМК.',
   'СМК СИ средства измерений поверка просрочено уведомление'),
  ('СМК','Что такое трассируемость в СМК?',
   'Трассируемость связывает изделие/партию с заявкой, паспортом, материалом и оператором: кто, из чего и когда сделал. Записи ведите на вкладке «Трассируемость» (можно из паспорта изделия). Это доказательная база для СМК и претензионной работы.',
   'трассируемость СМК изделие паспорт материал оператор партия')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and category='СМК');
