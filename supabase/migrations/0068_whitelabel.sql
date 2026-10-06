-- ============================================================
-- 3DMP Service · 0068_whitelabel.sql  (v46 — ЭПИК G: P6 white-label)
-- Брендирование организации: поддомен, логотип, цвет/тема, разрешение темы
-- по поддомену. База знаний. Зависит от 0001..0067.
-- ============================================================

alter table public.tenants add column if not exists subdomain text;
alter table public.tenants add column if not exists custom_domain text;
alter table public.tenants add column if not exists theme jsonb not null default '{}'::jsonb;

create unique index if not exists tenants_subdomain_idx on public.tenants (lower(subdomain)) where subdomain is not null;

-- ---------- Чтение/запись бренда организации ----------
create or replace function public.app_whitelabel_get(p_token uuid)
returns table (tenant_id uuid, name text, subdomain text, custom_domain text, plan text, status text,
               brand jsonb, theme jsonb)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole = 'admin' and ten is null then
    return query select t.id, t.name, t.subdomain, t.custom_domain, t.plan, t.status,
                        coalesce(t.brand,'{}'::jsonb), coalesce(t.theme,'{}'::jsonb)
      from public.tenants t order by t.created_at limit 1;
  end if;
  return query select t.id, t.name, t.subdomain, t.custom_domain, t.plan, t.status,
                      coalesce(t.brand,'{}'::jsonb), coalesce(t.theme,'{}'::jsonb)
    from public.tenants t where t.id = ten;
end $$;

create or replace function public.app_whitelabel_save(p_token uuid, p_subdomain text, p_custom_domain text,
  p_brand jsonb, p_theme jsonb)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; sd text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner') then return query select false,'Недостаточно прав'; return; end if;
  if ten is null then return query select false,'Организация не определена'; return; end if;
  sd := lower(nullif(trim(coalesce(p_subdomain,'')),''));
  if sd is not null and sd !~ '^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$' then
    return query select false,'Поддомен: только латиница, цифры и дефис'; return;
  end if;
  if sd is not null and exists (select 1 from public.tenants where lower(subdomain)=sd and id<>ten) then
    return query select false,'Поддомен уже занят'; return;
  end if;
  update public.tenants set subdomain=sd, custom_domain=nullif(trim(coalesce(p_custom_domain,'')),''),
    brand=coalesce(p_brand, brand), theme=coalesce(p_theme, theme)
   where id=ten;
  return query select true,'Брендирование сохранено';
end $$;

-- ---------- Разрешение темы по поддомену (для клиента, гость) ----------
create or replace function public.app_whitelabel_resolve(p_subdomain text)
returns table (tenant_id uuid, name text, brand jsonb, theme jsonb, plan text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare sd text;
begin
  sd := lower(nullif(trim(coalesce(p_subdomain,'')),''));
  if sd is null then return; end if;
  return query select t.id, t.name, coalesce(t.brand,'{}'::jsonb), coalesce(t.theme,'{}'::jsonb), t.plan
    from public.tenants t
    where (lower(t.subdomain)=sd or lower(t.custom_domain)=sd) and coalesce(t.status,'active')<>'suspended';
end $$;

grant execute on function public.app_whitelabel_get(uuid) to anon, authenticated;
grant execute on function public.app_whitelabel_save(uuid,text,text,jsonb,jsonb) to anon, authenticated;
grant execute on function public.app_whitelabel_resolve(text) to anon, authenticated;

-- ---------- Демо-тема (тенант A) ----------
update public.tenants
   set subdomain = coalesce(subdomain, 'demo'),
       theme = case when theme is null or theme='{}'::jsonb
         then jsonb_build_object('accent','#0e7490','logo','3DMP','slogan','Производство под ключ')
         else theme end
 where id = 'aaaaaaaa-0000-0000-0000-000000000001';

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','White-label — брендирование и поддомен (P6)',
   'Модуль «Брендирование»: организация задаёт поддомен (например 3dmp.sapfir.eu), свой домен, логотип, акцентный цвет и слоган. Тема хранится в tenants.theme и разрешается по поддомену (app_whitelabel_resolve) — клиент применяет бренд. Поддомен уникален.',
   'white-label бренд поддомен логотип тема цвет домен P6')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='White-label — брендирование и поддомен (P6)');
