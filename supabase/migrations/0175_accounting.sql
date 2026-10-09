-- ============================================================
-- 3DMP Service · 0175_accounting.sql  (W27 — Бухгалтерский/налоговый учёт, задел)
-- План счетов, проводки, оборотно-сальдовая ведомость, KPI.
-- Идемпотентно. Зависит от 0001..0174.
-- ============================================================

create table if not exists public.app_accounts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  code text not null, name text not null, kind text not null default 'asset', -- asset|liability|income|expense|equity
  created_at timestamptz default now()
);
create unique index if not exists app_accounts_uq on public.app_accounts (tenant_id, code);
alter table public.app_accounts enable row level security;

create table if not exists public.app_postings (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  number text, period_date date not null default current_date,
  debit_code text not null, credit_code text not null, amount numeric not null default 0,
  memo text, source text, entity_type text, entity_id uuid,
  created_login text, created_at timestamptz default now()
);
create index if not exists app_postings_idx on public.app_postings (tenant_id, period_date);
alter table public.app_postings enable row level security;

create or replace function public.app_accounts_list(p_token uuid)
returns table (id uuid, code text, name text, kind text)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm:=public.app_is_platform_admin(p_token); ten:=public.app_my_tenant(p_token);
  return query select a.id,a.code,a.name,a.kind from public.app_accounts a where adm or a.tenant_id=ten order by a.code;
end $$;

create or replace function public.app_account_save(p_token uuid, p_id uuid, p_code text, p_name text, p_kind text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; newid uuid; k text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',null::uuid; return; end if;
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id=s.uid;
  if coalesce(trim(p_code),'')='' or coalesce(trim(p_name),'')='' then return query select false,'Укажите код и название',null::uuid; return; end if;
  k:=coalesce(nullif(trim(p_kind),''),'asset');
  if k not in ('asset','liability','income','expense','equity') then return query select false,'Недопустимый тип счёта',null::uuid; return; end if;
  if p_id is null then
    insert into public.app_accounts (tenant_id,code,name,kind) values (ten,left(trim(p_code),20),left(trim(p_name),160),k) returning id into newid;
    return query select true,'Счёт добавлен',newid;
  else
    update public.app_accounts a set code=left(trim(p_code),20),name=left(trim(p_name),160),kind=k
     where a.id=p_id and (public.app_is_platform_admin(p_token) or a.tenant_id=ten) returning a.id into newid;
    if newid is null then return query select false,'Не найдено',null::uuid; return; end if;
    return query select true,'Счёт сохранён',newid;
  end if;
end $$;

create or replace function public.app_account_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten:=public.app_my_tenant(p_token);
  delete from public.app_accounts a where a.id=p_id and (public.app_is_platform_admin(p_token) or a.tenant_id=ten);
  get diagnostics n=row_count; if n=0 then return query select false,'Не найдено'; return; end if;
  return query select true,'Счёт удалён';
end $$;

create or replace function public.app_postings_list(p_token uuid, p_limit integer default 200)
returns table (id uuid, number text, period_date date, debit_code text, credit_code text, amount numeric, memo text, source text)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm:=public.app_is_platform_admin(p_token); ten:=public.app_my_tenant(p_token);
  return query select p.id,p.number,p.period_date,p.debit_code,p.credit_code,p.amount,p.memo,p.source
    from public.app_postings p where adm or p.tenant_id=ten order by p.period_date desc, p.created_at desc limit greatest(coalesce(p_limit,200),1);
end $$;

create or replace function public.app_posting_save(p_token uuid, p_id uuid, p_period date, p_debit text, p_credit text, p_amount numeric, p_memo text, p_source text, p_entity_type text, p_entity_id uuid)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; uname text; newid uuid; num text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',null::uuid; return; end if;
  select u.tenant_id,s.ulogin into ten,uname from public.app_session_user(p_token) s join public.app_users u on u.id=s.uid;
  if coalesce(trim(p_debit),'')='' or coalesce(trim(p_credit),'')='' then return query select false,'Укажите счета Дт и Кт',null::uuid; return; end if;
  if coalesce(p_amount,0)<=0 then return query select false,'Сумма должна быть > 0',null::uuid; return; end if;
  num := 'ПР-' || to_char(coalesce(p_period,current_date),'YYYY') || '-' || lpad((floor(random()*100000))::int::text,5,'0');
  insert into public.app_postings (tenant_id,number,period_date,debit_code,credit_code,amount,memo,source,entity_type,entity_id,created_login)
  values (ten,num,coalesce(p_period,current_date),trim(p_debit),trim(p_credit),p_amount,nullif(trim(p_memo),''),nullif(trim(p_source),''),nullif(trim(p_entity_type),''),p_entity_id,uname)
  returning id into newid;
  return query select true,'Проводка добавлена ('||num||')',newid;
end $$;

create or replace function public.app_posting_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten:=public.app_my_tenant(p_token);
  delete from public.app_postings p where p.id=p_id and (public.app_is_platform_admin(p_token) or p.tenant_id=ten);
  get diagnostics n=row_count; if n=0 then return query select false,'Не найдено'; return; end if;
  return query select true,'Проводка удалена';
end $$;

create or replace function public.app_trial_balance(p_token uuid, p_from date default null, p_to date default null)
returns table (code text, name text, debit numeric, credit numeric, balance numeric)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; adm boolean; d1 date; d2 date;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm:=public.app_is_platform_admin(p_token); ten:=public.app_my_tenant(p_token);
  d1:=coalesce(p_from,'1900-01-01'::date); d2:=coalesce(p_to,current_date);
  return query
    select a.code, a.name,
      (select coalesce(sum(p.amount),0) from public.app_postings p where (adm or p.tenant_id=ten) and p.debit_code=a.code and p.period_date between d1 and d2),
      (select coalesce(sum(p.amount),0) from public.app_postings p where (adm or p.tenant_id=ten) and p.credit_code=a.code and p.period_date between d1 and d2),
      (select coalesce(sum(p.amount),0) from public.app_postings p where (adm or p.tenant_id=ten) and p.debit_code=a.code and p.period_date between d1 and d2)
        - (select coalesce(sum(p.amount),0) from public.app_postings p where (adm or p.tenant_id=ten) and p.credit_code=a.code and p.period_date between d1 and d2)
      from public.app_accounts a where adm or a.tenant_id=ten order by a.code;
end $$;

create or replace function public.app_accounting_kpi(p_token uuid)
returns table (accounts bigint, postings bigint, turnover numeric)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm:=public.app_is_platform_admin(p_token); ten:=public.app_my_tenant(p_token);
  return query select
    (select count(*) from public.app_accounts a where adm or a.tenant_id=ten),
    (select count(*) from public.app_postings p where adm or p.tenant_id=ten),
    (select coalesce(sum(p.amount),0) from public.app_postings p where adm or p.tenant_id=ten);
end $$;

-- ---------- Демо ----------
insert into public.app_accounts (tenant_id, code, name, kind)
select v.tid::uuid, v.code, v.name, v.kind from (values
  ('aaaaaaaa-0000-0000-0000-000000000001','10','Материалы','asset'),
  ('aaaaaaaa-0000-0000-0000-000000000001','20','Основное производство','asset'),
  ('aaaaaaaa-0000-0000-0000-000000000001','60','Расчёты с поставщиками','liability'),
  ('aaaaaaaa-0000-0000-0000-000000000001','90','Продажи','income')
) as v(tid,code,name,kind)
where not exists (select 1 from public.app_accounts where tenant_id=v.tid::uuid and code=v.code);

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags, section)
select 'aaaaaaaa-0000-0000-0000-000000000001','Экономика','Бухгалтерский/налоговый учёт: план счетов, проводки, ОСВ (задел)',
       'W27 (задел): план счетов (app_accounts: тип asset/liability/income/expense/equity), проводки Дт/Кт (app_postings: период/сумма/источник/связь с объектом), оборотно-сальдовая ведомость (app_trial_balance: дебет/кредит/сальдо по счёту за период), KPI (app_accounting_kpi). Модуль «Бухгалтерия» (apps/accounting). Интеграция с 1С-бухгалтерией — через очередь обмена.',
       'бухгалтерия план счетов проводки ОСВ налоговый учёт задел','Экономика'
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Бухгалтерский/налоговый учёт: план счетов, проводки, ОСВ (задел)');

-- ---------- Права ----------
grant execute on function public.app_accounts_list(uuid) to anon, authenticated;
grant execute on function public.app_account_save(uuid,uuid,text,text,text) to anon, authenticated;
grant execute on function public.app_account_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_postings_list(uuid,integer) to anon, authenticated;
grant execute on function public.app_posting_save(uuid,uuid,date,text,text,numeric,text,text,text,uuid) to anon, authenticated;
grant execute on function public.app_posting_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_trial_balance(uuid,date,date) to anon, authenticated;
grant execute on function public.app_accounting_kpi(uuid) to anon, authenticated;
