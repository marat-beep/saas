-- ============================================================
-- 3DMP Service · 0085_config_options.sql  (v63 — Сессия N: A8 «Конфигуратор спец-технологий»)
-- Опции (группа → опция с наценкой) и расчёт стоимости конфигурации.
-- База знаний. Зависит от 0001..0084.
-- ============================================================

create table if not exists public.app_config_options (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  group_name  text not null,
  name        text not null,
  price_delta numeric not null default 0,
  note        text,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);
create index if not exists app_config_options_idx on public.app_config_options (tenant_id, group_name, active);
alter table public.app_config_options enable row level security;

create or replace function public.app_config_groups(p_token uuid)
returns table (group_name text, options bigint, price_min numeric, price_max numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select o.group_name, count(*), coalesce(min(o.price_delta),0), coalesce(max(o.price_delta),0)
    from public.app_config_options o
    where (urole='admin' or o.tenant_id=ten) and o.active
    group by o.group_name order by o.group_name;
end $$;

create or replace function public.app_config_options_list(p_token uuid, p_group text default null)
returns table (id uuid, group_name text, name text, price_delta numeric, note text, active boolean)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select o.id, o.group_name, o.name, o.price_delta, o.note, o.active
    from public.app_config_options o
    where (urole='admin' or o.tenant_id=ten)
      and (coalesce(p_group,'')='' or o.group_name=p_group)
    order by o.group_name, o.name;
end $$;

create or replace function public.app_config_option_save(p_token uuid, p_id uuid, p_group text, p_name text, p_price_delta numeric, p_note text, p_active boolean default true)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; oid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','technologist') then raise exception 'Недостаточно прав'; return; end if;
  if coalesce(trim(p_group),'')='' or coalesce(trim(p_name),'')='' then raise exception 'Укажите группу и название'; return; end if;
  if p_id is null then
    insert into public.app_config_options (tenant_id, group_name, name, price_delta, note, active)
    values (ten, trim(p_group), trim(p_name), coalesce(p_price_delta,0), nullif(trim(p_note),''), coalesce(p_active,true)) returning id into oid;
    return query select oid, 'Опция добавлена';
  else
    update public.app_config_options set group_name=trim(p_group), name=trim(p_name), price_delta=coalesce(p_price_delta,0),
      note=nullif(trim(p_note),''), active=coalesce(p_active,active)
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into oid;
    return query select oid, 'Опция обновлена';
  end if;
end $$;

create or replace function public.app_config_option_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_config_options where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Опция удалена';
end $$;

create or replace function public.app_config_estimate(p_token uuid, p_ids uuid[])
returns table (cnt int, total numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; c int; t numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select count(*), coalesce(sum(price_delta),0) into c, t
    from public.app_config_options o
    where (urole='admin' or o.tenant_id=ten) and o.id = any(coalesce(p_ids, array[]::uuid[]));
  return query select coalesce(c,0), coalesce(t,0);
end $$;

grant execute on function public.app_config_groups(uuid) to anon, authenticated;
grant execute on function public.app_config_options_list(uuid,text) to anon, authenticated;
grant execute on function public.app_config_option_save(uuid,uuid,text,text,numeric,text,boolean) to anon, authenticated;
grant execute on function public.app_config_option_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_config_estimate(uuid,uuid[]) to anon, authenticated;

-- ---------- Демо (тенант A) ----------
insert into public.app_config_options (tenant_id, group_name, name, price_delta, note)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.g, v.n, v.p, v.note
from (values
  ('Точность','Повышенная точность (IT6)', 15000, 'Доп. контроль и доводка'),
  ('Точность','Высокая точность (IT5)', 40000, 'Финишное шлифование/притирка'),
  ('Покрытие','Азотирование', 25000, 'Упрочнение поверхности'),
  ('Покрытие','Хромирование', 35000, 'Износостойкость'),
  ('Термообработка','Закалка + отпуск', 30000, 'HRC 45–50'),
  ('Термообработка','Стабилизация', 12000, 'Снятие напряжений'),
  ('Оснастка','Спецоснастка (проект)', 60000, 'Проектирование и изготовление'),
  ('Измерения','КИМ-контроль', 18000, 'Протокол измерений')
) as v(g,n,p,note)
where not exists (select 1 from public.app_config_options where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Продажи','Конфигуратор спец-технологий (A8)',
   'Модуль «Конфигуратор»: наборы опций по группам (точность, покрытие, термообработка, оснастка, измерения) с наценкой. Пользователь отмечает нужные опции — система считает суммарное удорожание. Основа быстрого расчёта спец-технологий и КП.',
   'конфигуратор опции спец-технологии точность покрытие термообработка наценка A8')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Конфигуратор спец-технологий (A8)');
