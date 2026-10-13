-- ============================================================
-- 3DMP Service · 0252_crm2.sql
-- X15 (остаток) · CRM: журнал контактов (звонки/письма/встречи) —
-- база для интеграции почты/телефонии через app_integrations.
-- Идемпотентно. Зависит от 0001..0251.
-- ============================================================

create table if not exists public.app_crm_contacts (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  deal_id     uuid references public.app_deals (id) on delete set null,
  customer_id uuid references public.app_customers (id) on delete set null,
  kind        text not null default 'note',      -- call|email|meeting|note
  direction   text not null default 'out',       -- in|out
  subject     text,
  body        text,
  at          timestamptz not null default now(),
  by_login    text
);
create index if not exists app_crm_contacts_idx on public.app_crm_contacts (tenant_id, deal_id, at desc);
alter table public.app_crm_contacts enable row level security;

create or replace function public.app_crm_contact_list(p_token uuid, p_deal_id uuid default null)
returns table (id uuid, deal_id uuid, deal text, customer text, kind text, direction text, subject text, body text, at timestamptz, by_login text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select k.id, k.deal_id, d.title, c.name, k.kind, k.direction, k.subject, k.body, k.at, k.by_login
    from public.app_crm_contacts k
    left join public.app_deals d on d.id = k.deal_id
    left join public.app_customers c on c.id = k.customer_id
   where (adm or k.tenant_id = ten) and (p_deal_id is null or k.deal_id = p_deal_id)
   order by k.at desc limit 200;
end $$;

create or replace function public.app_crm_contact_add(p_token uuid, p_deal_id uuid, p_customer_id uuid, p_kind text, p_direction text, p_subject text, p_body text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; uname text; nid uuid; cid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',null::uuid; return; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  select s.ulogin into uname from public.app_session_user(p_token) s;
  if coalesce(trim(p_subject),'') = '' and coalesce(trim(p_body),'') = '' then return query select false,'Укажите тему или текст',null::uuid; return; end if;
  if p_deal_id is not null then select d.customer_id into cid from public.app_deals d where d.id = p_deal_id and (adm or d.tenant_id = ten); end if;
  insert into public.app_crm_contacts (tenant_id, deal_id, customer_id, kind, direction, subject, body, by_login)
  values (ten, p_deal_id, coalesce(p_customer_id, cid), coalesce(nullif(trim(p_kind),''),'note'),
          case when p_direction='in' then 'in' else 'out' end, nullif(trim(p_subject),''), nullif(trim(p_body),''), uname)
  returning id into nid;
  return query select true, 'Контакт добавлен', nid;
end $$;

grant execute on function public.app_crm_contact_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_crm_contact_add(uuid,uuid,uuid,text,text,text,text) to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select null, v.category, v.question, v.answer, v.tags
from (values
  ('CRM','Журнал контактов CRM (почта/телефония)',
   'Журнал контактов фиксирует звонки, письма, встречи и заметки по сделке (app_crm_contacts): направление (входящий/исходящий), тема, текст, кто и когда. Список — app_crm_contact_list (фильтр по сделке), добавление — app_crm_contact_add. Журнал — задел под интеграцию почты/телефонии через app_integrations (входящие события пишутся сюда).',
   'CRM контакты звонки письма журнал почта телефония app_crm_contacts app_integrations')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge k where k.question=v.question);
