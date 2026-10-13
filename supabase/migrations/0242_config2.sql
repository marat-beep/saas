-- ============================================================
-- 3DMP Service · 0242_config2.sql
-- X15 (остаток) · Конфигуратор: шаблоны конфигураций (с КП из шаблона)
-- и историчность цен опций.
--  • app_config_presets + preset_list/save/delete/quote (КП из шаблона).
--  • app_config_price_history + app_config_option_save с логированием цены.
-- Идемпотентно. Зависит от 0001..0241.
-- ============================================================

create table if not exists public.app_config_presets (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  name       text not null,
  options    jsonb not null default '[]'::jsonb,
  total      numeric not null default 0,
  note       text,
  created_by text,
  created_at timestamptz not null default now()
);
create index if not exists app_config_presets_idx on public.app_config_presets (tenant_id, created_at desc);
alter table public.app_config_presets enable row level security;

create table if not exists public.app_config_price_history (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  option_id  uuid references public.app_config_options (id) on delete cascade,
  option_name text,
  old_price  numeric,
  new_price  numeric,
  by_login   text,
  at         timestamptz not null default now()
);
create index if not exists app_config_price_hist_idx on public.app_config_price_history (option_id, at desc);
alter table public.app_config_price_history enable row level security;

-- ---------- Логирование цены при сохранении опции ----------
create or replace function public.app_config_option_save(p_token uuid, p_id uuid, p_group text, p_name text, p_price_delta numeric, p_note text, p_active boolean default true)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; oid uuid; oldp numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','technologist') then raise exception 'Недостаточно прав'; return; end if;
  if coalesce(trim(p_group),'')='' or coalesce(trim(p_name),'')='' then raise exception 'Укажите группу и название'; return; end if;
  if p_id is null then
    insert into public.app_config_options (tenant_id, group_name, name, price_delta, note, active)
    values (ten, trim(p_group), trim(p_name), coalesce(p_price_delta,0), nullif(trim(p_note),''), coalesce(p_active,true)) returning id into oid;
    insert into public.app_config_price_history (tenant_id, option_id, option_name, old_price, new_price, by_login)
    select ten, oid, trim(p_name), null, coalesce(p_price_delta,0), s.ulogin from public.app_session_user(p_token) s;
    return query select oid, 'Опция добавлена';
  else
    select price_delta into oldp from public.app_config_options where id = p_id and (urole='admin' or tenant_id=ten);
    update public.app_config_options set group_name=trim(p_group), name=trim(p_name), price_delta=coalesce(p_price_delta,0),
      note=nullif(trim(p_note),''), active=coalesce(p_active,active)
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into oid;
    if oid is null then return query select null::uuid, 'Опция не найдена'; return; end if;
    if coalesce(p_price_delta,0) is distinct from oldp then
      insert into public.app_config_price_history (tenant_id, option_id, option_name, old_price, new_price, by_login)
      select ten, oid, trim(p_name), oldp, coalesce(p_price_delta,0), s.ulogin from public.app_session_user(p_token) s;
    end if;
    return query select oid, 'Опция обновлена';
  end if;
end $$;

create or replace function public.app_config_price_history_list(p_token uuid, p_option_id uuid default null)
returns table (option_id uuid, option_name text, old_price numeric, new_price numeric, by_login text, at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select h.option_id, h.option_name, h.old_price, h.new_price, h.by_login, h.at
    from public.app_config_price_history h
   where (adm or h.tenant_id = ten) and (p_option_id is null or h.option_id = p_option_id)
   order by h.at desc limit 200;
end $$;

-- ---------- Шаблоны конфигураций ----------
create or replace function public.app_config_preset_list(p_token uuid)
returns table (id uuid, name text, cnt integer, total numeric, note text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select p.id, p.name, coalesce(jsonb_array_length(p.options),0)::int, p.total, p.note, p.created_at
    from public.app_config_presets p where (adm or p.tenant_id = ten) order by p.created_at desc;
end $$;

create or replace function public.app_config_preset_save(p_token uuid, p_id uuid, p_name text, p_options jsonb, p_total numeric, p_note text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; uname text; nid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',null::uuid; return; end if;
  if not exists (select 1 from public.app_session_user(p_token) s where s.urole in ('admin','owner','manager','director','technologist')) then return query select false,'Нет прав на конфигуратор',null::uuid; return; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  select s.ulogin into uname from public.app_session_user(p_token) s;
  if coalesce(trim(p_name),'') = '' then return query select false,'Укажите название шаблона',null::uuid; return; end if;
  if p_id is null then
    insert into public.app_config_presets (tenant_id, name, options, total, note, created_by)
    values (ten, left(trim(p_name),160), coalesce(p_options,'[]'::jsonb), coalesce(p_total,0), nullif(trim(p_note),''), uname)
    returning id into nid;
    return query select true,'Шаблон сохранён', nid;
  else
    update public.app_config_presets set name=left(trim(p_name),160), options=coalesce(p_options,options),
      total=coalesce(p_total,total), note=nullif(trim(p_note),'')
     where id=p_id and (adm or tenant_id=ten) returning id into nid;
    if nid is null then return query select false,'Шаблон не найден',null::uuid; return; end if;
    return query select true,'Шаблон обновлён', nid;
  end if;
end $$;

create or replace function public.app_config_preset_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  if not exists (select 1 from public.app_session_user(p_token) s where s.urole in ('admin','owner','manager','director','technologist')) then return query select false,'Нет прав'; return; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  delete from public.app_config_presets where id=p_id and (adm or tenant_id=ten);
  return query select true,'Шаблон удалён';
end $$;

-- КП из шаблона: пересчёт по актуальным ценам и создание документа
create or replace function public.app_config_preset_quote(p_token uuid, p_id uuid)
returns table (ok boolean, message text, number text, total numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; p record; ids uuid[]; c int; t numeric; content text; num text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',null::text, null::numeric; return; end if;
  if not exists (select 1 from public.app_session_user(p_token) s where s.urole in ('admin','owner','manager','director','technologist')) then return query select false,'Нет прав',null::text, null::numeric; return; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  select * into p from public.app_config_presets where id = p_id and (adm or tenant_id = ten);
  if p.id is null then return query select false,'Шаблон не найден',null::text, null::numeric; return; end if;
  -- собрать id опций из jsonb (массив uuid или строк)
  select array_agg((e)::uuid) into ids
    from jsonb_array_elements_text(coalesce(p.options,'[]'::jsonb)) e
   where (e) ~* '^[0-9a-f-]{36}$';
  select count(*), coalesce(sum(price_delta),0) into c, t
    from public.app_config_options o
   where (adm or o.tenant_id = ten) and o.active and o.id = any(coalesce(ids, array[]::uuid[]));
  select string_agg('• ' || o.group_name || ': ' || o.name || ' (+' || o.price_delta || ' ₽)', chr(10) order by o.group_name, o.name) into content
    from public.app_config_options o
   where (adm or o.tenant_id = ten) and o.active and o.id = any(coalesce(ids, array[]::uuid[]));
  content := 'Коммерческое предложение по конфигурации: ' || p.name || chr(10)
          || 'Опций: ' || coalesce(c,0) || ' · Наценка: ' || coalesce(t,0) || ' ₽' || chr(10) || coalesce(content,'');
  select d.number into num from public.app_doc_create(p_token, 'kp', 'КП: ' || p.name, null, null, coalesce(t,0), content) d;
  return query select true, 'КП создано', num, coalesce(t,0);
end $$;

grant execute on function public.app_config_option_save(uuid,uuid,text,text,numeric,text,boolean) to anon, authenticated;
grant execute on function public.app_config_price_history_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_config_preset_list(uuid) to anon, authenticated;
grant execute on function public.app_config_preset_save(uuid,uuid,text,jsonb,numeric,text) to anon, authenticated;
grant execute on function public.app_config_preset_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_config_preset_quote(uuid,uuid) to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select null, v.category, v.question, v.answer, v.tags
from (values
  ('Конфигуратор','Шаблоны конфигураций и историчность цен',
   'Конфигуратор: набор выбранных опций можно сохранить как шаблон (app_config_presets) и в один клик сформировать КП по актуальным ценам (app_config_preset_quote → документ КП). Изменения цен опций пишутся в историю app_config_price_history (кто, старая/новая цена, когда) — список app_config_price_history_list. UI: «Сохранить как шаблон», «Шаблоны» (загрузить/КП/удалить), «История цен».',
   'конфигуратор шаблоны конфигураций КП из шаблона историчность цен app_config_presets app_config_price_history')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge k where k.question=v.question);
