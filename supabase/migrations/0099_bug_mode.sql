-- ============================================================
-- 3DMP Service · 0099_bug_mode.sql  (v78 — Bug Mode: баги поверх замечаний)
-- Расширяем app_page_remarks (kind/payload/status) и добавляем RPC для багов.
-- Диагностический конверт Report хранится в payload jsonb. Зависит 0001..0098.
-- ============================================================

alter table public.app_page_remarks add column if not exists kind text not null default 'remark'; -- remark|bug
alter table public.app_page_remarks add column if not exists payload jsonb;
alter table public.app_page_remarks add column if not exists status text not null default 'new';  -- new|in_work|fixed|rejected (для багов)

create or replace function public.app_bug_create(p_token uuid, p_module text, p_url text, p_x numeric, p_y numeric,
  p_role_name text, p_author text, p_type text, p_text text, p_payload jsonb)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; ulogin text; rid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.ulogin into ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  insert into public.app_page_remarks (tenant_id, module, url, x, y, role, role_name, author, type, text, kind, payload, status, created_login)
  values (ten, nullif(trim(p_module),''), nullif(trim(p_url),''), coalesce(p_x,0), coalesce(p_y,0), 'employee',
          nullif(trim(p_role_name),''), nullif(trim(p_author),''), coalesce(nullif(trim(p_type),''),'Ошибка'), nullif(trim(p_text),''),
          'bug', coalesce(p_payload,'{}'::jsonb), 'new', ulogin)
  returning id into rid;
  if ten is not null then
    perform public.app_notif_roles_t(ten, array['admin','owner','manager'], 'Новый баг: '||coalesce(nullif(trim(p_text),''),'без описания'), coalesce(p_url,''), 'apps/bugbox/index.html');
  end if;
  return query select rid, 'Баг передан разработчику';
end $$;

create or replace function public.app_bug_list(p_token uuid, p_status text default null, p_module text default null)
returns table (id uuid, module text, url text, x numeric, y numeric, author text, type text, text text, status text, payload jsonb, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select r.id, r.module, r.url, r.x, r.y, r.author, r.type, r.text, r.status, r.payload, r.created_at
    from public.app_page_remarks r
    where (urole='admin' or r.tenant_id=ten) and r.kind='bug'
      and (coalesce(p_status,'')='' or r.status=p_status)
      and (coalesce(p_module,'')='' or r.module=p_module)
    order by r.created_at desc;
end $$;

create or replace function public.app_bug_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  if not public.app_can(p_token,'platform','edit') then return query select false,'Недостаточно прав'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if p_status not in ('new','in_work','fixed','rejected') then return query select false,'Неверный статус'; return; end if;
  update public.app_page_remarks set status=p_status, updated_at=now() where id=p_id and kind='bug' and (urole='admin' or tenant_id=ten);
  return query select true,'Статус баг-репорта обновлён';
end $$;

create or replace function public.app_bug_kpi(p_token uuid)
returns table (total bigint, new_cnt bigint, in_work bigint, fixed bigint, rejected bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select count(*), count(*) filter (where status='new'), count(*) filter (where status='in_work'),
    count(*) filter (where status='fixed'), count(*) filter (where status='rejected')
    from public.app_page_remarks where kind='bug' and (urole='admin' or tenant_id=ten);
end $$;

grant execute on function public.app_bug_create(uuid,text,text,numeric,numeric,text,text,text,text,jsonb) to anon, authenticated;
grant execute on function public.app_bug_list(uuid,text,text) to anon, authenticated;
grant execute on function public.app_bug_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_bug_kpi(uuid) to anon, authenticated;

insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Bug Mode и баг-репорты',
   'Режим бага: клик по элементу собирает CSS-селектор, console-ошибки и breadcrumbs, формирует диагностический конверт Report и передаёт разработчику (PDF + JSON + deep-link + уведомление). Баги хранятся в app_page_remarks (kind=bug, payload, статусы new/in_work/fixed/rejected), дашборд — apps/bugbox.',
   'bug mode баг репорт report конверт селектор console breadcrumbs bugbox')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Bug Mode и баг-репорты');
